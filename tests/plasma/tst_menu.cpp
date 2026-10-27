#include <QApplication>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonArray>
#include <QFile>
#include <sys/resource.h>
#include <unistd.h>
#include <QDebug>
#include <QWheelEvent>
#include <QElapsedTimer>
#include <QSignalSpy>
#include <KColorScheme>
#include <KSharedConfig>
#include <functional>
#include <algorithm>
#include <cmath>
#include <QQmlContext>
#include <QQmlExpression>
#include <QtTest/QTest>
#include <Plasma/Applet>
#include <Plasma/Corona>
#include <Plasma/Containment>
class TestCorona : public Plasma::Corona {
public:
 QRect screenGeometry(uint) const override {
   const int w = qEnvironmentVariableIntValue("FENESTRA_TEST_SCREEN_WIDTH");
   return QRect(0, 0, w > 0 ? w : 1366, 900);
 }
};
#include <Plasma/PluginLoader>
#include <PlasmaQuick/AppletQuickItem>
int main(int argc, char **argv) {
 qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &msg) { fprintf(stderr, "%s\n", qPrintable(msg)); });
 QApplication app(argc, argv);
 const double fontScale = qEnvironmentVariable("FENESTRA_TEST_FONT_SCALE", "1").toDouble();
 if (fontScale != 1) { auto f = app.font(); f.setPointSizeF(f.pointSizeF() * fontScale); app.setFont(f); }
 const QString scheme = qEnvironmentVariable("FENESTRA_TEST_SCHEME");
 if (!scheme.isEmpty()) app.setPalette(KColorScheme::createApplicationPalette(KSharedConfig::openConfig(scheme, KConfig::SimpleConfig)));
 const QString output = qEnvironmentVariable("FENESTRA_TEST_OUTPUT", "/tmp");
 TestCorona corona;
 auto containment = corona.createContainment("org.kde.panel");
 containment->setScreen(0);
 auto applet = containment->createApplet("org.fenestra.menu11");
 if (!applet) return 2;
 applet->init();
 auto item = PlasmaQuick::AppletQuickItem::itemForApplet(applet);
 if (!item) { qCritical() << "no item"; return 3; }
 QQuickWindow window;
 item->setParentItem(window.contentItem());
 item->setSize(QSizeF(48,48)); window.resize(48,48); window.show();
 QTest::qWait(800);
 auto compact = item->compactRepresentationItem();
 if (!compact) compact = item->fullRepresentationItem();
 if (!compact) return 4;
 auto popup = compact->property("dashWindow").value<QObject*>();
 if (!popup) return 5;
 popup->setProperty("visible", true);
 QTest::qWait(1000);

 auto field = popup->findChild<QObject*>("searchField");
 if (!field) return 6;
 auto eval = [&](const QString &source) {
   QQmlExpression expression(qmlContext(field), field, source);
   auto value = expression.evaluate();
   if (expression.hasError()) { qCritical() << expression.error(); std::exit(8); }
   return value;
 };
 if (qEnvironmentVariableIsSet("FENESTRA_TEST_LONG_LABELS")) {
   eval("rootItem.availableCategories = rootItem.availableCategories.map(function(entry){ return {row:entry.row, label:'Applications and development tools with a very long localized category name: '+entry.label, icon:entry.icon}; });");
 }
 if (app.arguments().contains("--large")) {
   eval("var batch = []; for (var k=0; k<2000; ++k) batch.push({itemType:'app', display:'Synthetic application ' + k + ' with a deliberately long localized-style name', decoration:k%7 ? 'application-x-executable' : 'missing-test-icon', favoriteId:'fixture-' + k + '.desktop', description:'Synthetic collection for rendering tests', url:'', disabled:false, hasActionList:false, sourceRow:-1, folderIdx:-1, indented:false, expanded:false}); allAppsListModel.append(batch); allAppsGridModel.append(batch);");
   QTest::qWait(100);
 }
 if (app.arguments().contains("--benchmark")) {
   auto measure = [&](const QString &name, int n, const std::function<void(int)> &operation) {
     QList<double> samples;
     for (int i = 0; i < n; ++i) {
       QElapsedTimer timer;
       timer.start();
       operation(i);
       QCoreApplication::processEvents();
       if (auto w = qobject_cast<QQuickWindow*>(popup)) w->grabWindow();
       samples.append(timer.nsecsElapsed() / 1000000.0);
       QTest::qWait(10);
     }
     std::sort(samples.begin(), samples.end());
     qInfo().noquote() << "BENCH" << name << "n" << n << "median_ms" << samples[n/2]
                      << "p95_ms" << samples[qMin(n-1, int(std::ceil(n*0.95))-1)];
   };
   auto rssKiB = []() -> qint64 {
     QFile file("/proc/self/statm");
     if (!file.open(QIODevice::ReadOnly)) return -1;
     const auto fields = file.readAll().simplified().split(' ');
     return fields.size()>1 ? fields[1].toLongLong() * sysconf(_SC_PAGESIZE) / 1024 : -1;
   };
   const qint64 rssBefore = rssKiB();
   measure("view_switch", 20, [&](int i) {eval(QString("rootItem.setAppsViewMode(%1)").arg(i%2 ? 0:1));});
   eval("rootItem.setAppsViewMode(0)");
   measure("category_switch", 20, [&](int i) {eval(QString("rootItem.selectCategory(%1)").arg(i%2 ? -1 : eval("rootItem.availableCategories[1].row").toInt()));});
   eval("rootItem.selectCategory(-1)");
   measure("scroll", 20, [&](int i) {eval(QString("mainFlick.scrollBy(%1)").arg(i%2 ? 150:-150));});
   measure("warm_open", 20, [&](int) {popup->setProperty("visible", false); popup->setProperty("visible", true);});
   auto fieldItem = qobject_cast<QQuickItem*>(field);
   measure("search_input", 20, [&](int i) {fieldItem->forceActiveFocus();eval(i%2 ? "searchField.text = ''" : "searchField.text = 'dolphin'");});
   eval("searchField.text = ''");
   popup->setProperty("visible", false);
   rusage startUsage{}, endUsage{};
   getrusage(RUSAGE_SELF, &startUsage);
   QTest::qWait(2000);
   getrusage(RUSAGE_SELF, &endUsage);
   auto cpu = [](const rusage &usage) {
     return (usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000.0
            + (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000.0;
   };
   qInfo() << "RESOURCE" << "rss_before_KiB" << rssBefore << "rss_after_KiB" << rssKiB()
           << "closed_idle_wall_ms" << 2000 << "closed_idle_cpu_ms" << cpu(endUsage)-cpu(startUsage);
   return 0;
 }
 int failures = 0;
 auto check = [&](const QString &name, const QString &source) {
   bool ok = eval(source).toBool();
   qInfo() << (ok ? "PASS" : "FAIL") << name;
   failures += !ok;
 };
 qInfo() << "NATIVE_AVAILABLE" << eval("root.core !== null && root.core.available");
 qInfo() << "METRICS" << eval("JSON.stringify({count: allAppsGrid.count, width: allAppsGrid.width, cell: allAppsGrid.cellWidth, height: mainFlick.height, content: mainFlick.contentHeight, pinnedBottom: globalFavoritesGrid.y + globalFavoritesGrid.height, appsTop: allAppsHeader.y, controls: categoryControls.height})");
 check("core facade reaches popup", "root.core !== null");
 check("catalog populated", "allAppsGrid.count > 0");
 check("list fits viewport", "allAppsGrid.cellWidth <= allAppsGrid.width");
 check("recent files disabled", "rootModel.showRecentDocs === false");
 check("recent app preference preserved", "Plasmoid.configuration.showRecentApps === false");
 auto popupWindow = qobject_cast<QQuickWindow*>(popup);
 if (popupWindow) popupWindow->grabWindow().save(output + "/list.png");
 std::function<QQuickItem*(QQuickItem*, const QString&)> findVisual = [&](QQuickItem *parent, const QString &name) -> QQuickItem* {
   if (parent->objectName() == name) return parent;
   for (auto child : parent->childItems()) if (auto found = findVisual(child, name)) return found;
   return nullptr;
 };
 auto clickButton = [&](const char *name) {
   auto button = findVisual(popupWindow->contentItem(), QString::fromUtf8(name));
   if (!button || !popupWindow) std::exit(9);
   qInfo() << "CLICK" << name << button->mapToScene(QPointF(button->width()/2,button->height()/2));
   QTest::mouseClick(popupWindow, Qt::LeftButton, Qt::NoModifier,
                     button->mapToScene(QPointF(button->width()/2,button->height()/2)).toPoint());
   QTest::qWait(200);
 };
 clickButton("appsGridButton");
 check("grid selected", "Plasmoid.configuration.allAppsViewMode === 1 && allAppsGrid.columnsCount > 1");
 check("grid has apps", "allAppsGrid.count > 0 && allAppsGrid.cellWidth <= allAppsGrid.width");
 if (popupWindow) popupWindow->grabWindow().save(output + "/grid.png");
 auto gridItem = popup->findChild<QQuickItem*>("allAppsGrid");
 QPointF wheelPos = gridItem->mapToScene(QPointF(40, 30));
 QWheelEvent wheel(wheelPos, popupWindow->mapToGlobal(wheelPos.toPoint()), QPoint(), QPoint(0,-120),
                   Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
 QCoreApplication::sendEvent(popupWindow, &wheel);
 QTest::qWait(100);
 check("page scroll moves", "mainFlick.contentY > 0");
 check("visible rows track outer scroll", "Math.abs(allAppsGrid.contentY - allAppsGrid.viewportOffset) < 1");
 eval("root.scrollToLetter('S')"); QTest::qWait(260);
 if (popupWindow) popupWindow->grabWindow().save(output + "/scrolled-grid.png");
 check("alphabet scroll moves page", "mainFlick.contentY > 200 && Math.abs(allAppsGrid.contentY - allAppsGrid.viewportOffset) < 1");
 eval("mainFlick.cancelFlick(); scrollAnim.stop(); letterScrollAnim.stop(); mainFlick.contentY = 0"); QTest::qWait(100);
 clickButton("appsListButton");
 qInfo() << "AFTER_LIST_CLICK" << eval("JSON.stringify({mode:Plasmoid.configuration.allAppsViewMode,cols:allAppsGrid.columnsCount,scroll:mainFlick.contentY,width:allAppsGrid.width,cell:allAppsGrid.cellWidth})");
 check("list selected", "Plasmoid.configuration.allAppsViewMode === 0 && allAppsGrid.columnsCount === 1");
 check("list virtualizes delegates", "allAppsGrid.renderedItemCount < allAppsGrid.count");
 auto listModel = eval("allAppsListModel").value<QObject*>();
 QSignalSpy resets(listModel, SIGNAL(modelReset()));
 QSignalSpy removals(listModel, SIGNAL(rowsRemoved(QModelIndex,int,int)));
 QElapsedTimer switchTimer;
 qint64 slowestSwitch = 0;
 for (int mode : {1,0,1,0,1,0}) {
   switchTimer.start();
   eval(QString("rootItem.setAppsViewMode(%1)").arg(mode));
   QCoreApplication::processEvents();
   slowestSwitch = qMax(slowestSwitch, switchTimer.elapsed());
 }
 qInfo() << "SLOWEST_LIST_GRID_SWITCH_MS" << slowestSwitch;
 check("switch keeps catalog cache", resets.count() == 0 && removals.count() == 0 ? "true" : "false");
 clickButton("appsCategoriesButton");
 check("categories selected", "Plasmoid.configuration.allAppsViewMode === 2 && allAppsCategoryGrid.visible");
 QTest::qWait(100);
 if (popupWindow) popupWindow->grabWindow().save(output + "/categories.png");
 clickButton("appsListButton");
 clickButton("categoryDropdownButton");
 check("category dropdown opens", "viewModePopup.visible");
 check("category dropdown stays inside launcher", "viewModePopup.x >= 0 && viewModePopup.y >= 0 && viewModePopup.y + viewModePopup.height <= rootItem.height && viewModePopup.x + viewModePopup.width <= rootItem.width");
 if (popupWindow) popupWindow->grabWindow().save(output + "/dropdown.png");
 QTest::keyClick(popupWindow, Qt::Key_Down);
 QTest::keyClick(popupWindow, Qt::Key_Return);
 check("dropdown keyboard selects category", "rootItem.activeCategoryRow === rootItem.availableCategories[1].row && !viewModePopup.visible");
 check("dropdown restores trigger focus", "categoryDropButton.activeFocus");
 eval("rootItem.selectCategory(-1)");
 clickButton("categoryDropdownButton");
 QTest::keyClick(popupWindow, Qt::Key_Escape);
 check("dropdown Escape dismisses", "!viewModePopup.visible && root.visible");
 eval("rootItem.selectCategory(rootItem.availableCategories[1].row)");
 check("category caches rows", "rootItem.categoryRowsCache[rootItem.activeCategoryRow] !== undefined");
 eval("rootItem.selectCategory(-1)");
 check("only app and setting runners", "runnerModel.runners.length === 2 && runnerModel.runners.indexOf('krunner_services') >= 0 && runnerModel.runners.indexOf('krunner_systemsettings') >= 0");
 eval("rootItem.newApps = {}; var rows = rootItem.availableCategories; var row = rows[1].row; var fid = Object.keys(rootItem.categoryMembership[row])[0]; var marked = {}; marked[fid] = {t: Date.now(), cat: rows[1].label, name: fid}; rootItem.newApps = marked;");
 QTest::qWait(100);
 check("category badge marks matching category", "!!rootItem.categoriesWithNewApps[rootItem.availableCategories[1].row]");
 check("category badge marks all apps", "!!rootItem.categoriesWithNewApps[-1]");
 auto dot = findVisual(popupWindow->contentItem(), "categoryNewDot_" + eval("rootItem.availableCategories[1].row").toString());
 check("category dot visible", dot && dot->isVisible() ? "true" : "false");
 if (popupWindow) popupWindow->grabWindow().save(output + "/category-badge.png");
 eval("rootItem.forgetNewApp(Object.keys(rootItem.newApps)[0])");
 check("badge clears when app acknowledged", "Object.keys(rootItem.categoriesWithNewApps).length === 0");
 auto fieldItem = qobject_cast<QQuickItem*>(field);
 fieldItem->forceActiveFocus();
 for (QChar c : QStringLiteral("dolphin")) QTest::keyClick(popupWindow, static_cast<Qt::Key>(c.toUpper().unicode())); QTest::qWait(2000);
 check("typing keeps search focus", "searchField.activeFocus");
 check("search query delivered", "runnerModel.query === 'dolphin'");
 check("search page active", "view.currentIndex === 1");
 check("search results exist", "runnerGrid.count > 0");
 check("search cells fit", "runnerGrid.cellWidth <= runnerGrid.availableWidth");
 qInfo() << "SEARCH" << eval("JSON.stringify({sections: runnerGrid.count, firstCount: runnerGrid.count > 0 ? runnerGrid.subGridAt(0).count : 0})");
 if (popupWindow) popupWindow->grabWindow().save(output + "/search.png");
 eval("searchField.text = ''");
 check("clear resets immediately", "runnerModel.query === '' && view.currentIndex === 0 && rootItem.pluginResults.length === 0 && !searchDebounce.running");
 eval("searchField.text = 'kate'; searchField.text = '/';"); QTest::qWait(150);
 check("palette cancels pending search", "runnerModel.query === '' && !searchDebounce.running");
 eval("searchField.text = '   '");
 check("whitespace leaves home visible", "!root.searching && view.currentIndex === 0 && runnerModel.query === ''");

 eval("searchField.text = ''; rootItem.selectCategory(-1); rootItem.setAppsViewMode(0); mainFlick.contentY = 0;");
 const QString fixtureQml = R"QML(import QtQuick
 ListModel {
   id: fixture
   signal launched(int row)
   property var favoritesModel: fixture
   property int maxFavorites: -1
   property var favorites: []
   function trigger(row, actionId, argument) { launched(row); }
   function isFavorite(id) { return favorites.indexOf(id) >= 0; }
   function addFavorite(id) {
     if (isFavorite(id)) return;
     favorites = favorites.concat([id]);
     append({display: id.indexOf('long')>=0 ? 'A very long application name that must stay inside its tile and expose a tooltip' : id,
             decoration:'missing-fixture-icon', favoriteId:id, description:'Fixture application', url:'', disabled:false});
   }
   function removeFavorite(id) {
     var row = favorites.indexOf(id); if (row < 0) return;
     var copy=favorites.slice(); copy.splice(row,1); favorites=copy; remove(row);
   }
   function moveRow(from,to) {
     move(from,to,1); var copy=favorites.slice(); var entry=copy.splice(from,1)[0]; copy.splice(to,0,entry); favorites=copy;
   }
 })QML";
 const auto encoded = QString::fromUtf8(QJsonDocument(QJsonArray{fixtureQml}).toJson(QJsonDocument::Compact));
 eval("globalFavoritesGrid.model = Qt.createQmlObject(" + encoded.mid(1, encoded.size()-2) + ", rootItem); globalFavoritesGrid.model.addFavorite('long-fixture.desktop'); globalFavoritesGrid.model.addFavorite('second-fixture.desktop');");
 QTest::qWait(100);
 check("pinned favorites add", "globalFavoritesGrid.count === 2");
 eval("globalFavoritesGrid.model.moveRow(0,1)");
 check("pinned reorder", "globalFavoritesGrid.model.get(0).favoriteId === 'second-fixture.desktop'");
 eval("globalFavoritesGrid.model.removeFavorite('second-fixture.desktop')");
 check("pinned unpin", "globalFavoritesGrid.count === 1");
 if (popupWindow) popupWindow->grabWindow().save(output + "/pinned.png");
 eval("rootItem.lastNavKeyTime = Date.now(); globalFavoritesGrid.tryActivate(0,0); globalFavoritesGrid.forceActiveFocus(); globalFavoritesGrid.currentItem.openActionMenu(10,10);");
 QTest::qWait(80);
 auto pinnedGrid = popup->findChild<QObject*>("globalFavoritesGrid");
 auto context = pinnedGrid->findChild<QObject*>("launcherActionMenu");
 check("pinned context menu opens", context && context->property("opened").toBool() ? "true" : "false");
 if (context) {
   if (auto menu = context->property("menu").value<QObject*>()) QMetaObject::invokeMethod(menu, "close");
 }
 auto fixtureModel = eval("globalFavoritesGrid.model").value<QObject*>();
 QSignalSpy launched(fixtureModel, SIGNAL(launched(int)));
 popup->setProperty("visible", true);
 QTest::qWait(50);
 auto pinnedItem = qobject_cast<QQuickItem*>(pinnedGrid);
 const QPoint pinnedPoint = pinnedItem->mapToScene(QPointF(eval("globalFavoritesGrid.cellWidth").toDouble()/2,
                                                          eval("globalFavoritesGrid.cellHeight").toDouble()/2)).toPoint();
 QTest::mouseClick(popupWindow, Qt::LeftButton, Qt::NoModifier, pinnedPoint);
 check("pinned launch dispatched exactly once", launched.count() == 1 ? "true" : "false");
 popup->setProperty("visible", true);
 launched.clear();
 eval("rootItem.lastNavKeyTime = Date.now(); globalFavoritesGrid.tryActivate(0,0); globalFavoritesGrid.forceActiveFocus();");
 QTest::keyClick(popupWindow, Qt::Key_Return);
 check("keyboard launch dispatched exactly once", launched.count() == 1 ? "true" : "false");
 popup->setProperty("visible", true);
 eval("globalFavoritesGrid.model = globalFavorites; rootItem.allAppsFoldersData = [{name:'Fixture folder',items:['org.kde.dolphin.desktop'],createdAt:1}]; rootItem.buildAllAppsCombo();");
 const int folderRow = eval("(function(){for(var i=0; i<rootItem.allAppsComboModel.count; ++i) if(rootItem.allAppsComboModel.get(i).itemType==='folder') return i; return -1;})()").toInt();
 eval(QString("rootItem.toggleFolderExpand(%1)").arg(folderRow));
 check("app folder expands", QString("rootItem.allAppsComboModel.get(%1).expanded && rootItem.allAppsComboModel.get(%2).indented").arg(folderRow).arg(folderRow+1));
 eval(QString("rootItem.toggleFolderExpand(%1)").arg(folderRow));
 check("app folder collapses", QString("!rootItem.allAppsComboModel.get(%1).expanded").arg(folderRow));
 eval("rootItem.allAppsFoldersData = []; rootItem.pinnedFoldersData = [{name:'Pinned folder',items:['org.kde.dolphin.desktop']}];");
 check("pinned folder retained", "folderStrip.visible");
 eval("rootItem.pinnedFoldersData = [];");
 popup->setProperty("visible", false);
 check("closed launcher has no app scan timer", "!appsWatchTimer.running");
 qInfo() << "FAILURES" << failures;
 return failures ? 7 : 0;
}
