#include <QApplication>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTimer>
#include <QDebug>
#include <QWheelEvent>
#include <QQmlContext>
#include <QQmlExpression>
#include <QtTest/QTest>
#include <Plasma/Applet>
#include <Plasma/Corona>
#include <Plasma/Containment>
class TestCorona : public Plasma::Corona { public: QRect screenGeometry(uint) const override {return QRect(0,0,1366,768);} };
#include <Plasma/PluginLoader>
#include <PlasmaQuick/AppletQuickItem>
int main(int argc, char **argv) {
 qInstallMessageHandler([](QtMsgType, const QMessageLogContext &, const QString &msg) { fprintf(stderr, "%s\n", qPrintable(msg)); });
 QApplication app(argc, argv);
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
 int failures = 0;
 auto check = [&](const QString &name, const QString &source) {
   bool ok = eval(source).toBool();
   qInfo() << (ok ? "PASS" : "FAIL") << name;
   failures += !ok;
 };
 qInfo() << "METRICS" << eval("JSON.stringify({count: allAppsGrid.count, width: allAppsGrid.width, cell: allAppsGrid.cellWidth, height: mainFlick.height, content: mainFlick.contentHeight, pinnedBottom: globalFavoritesGrid.y + globalFavoritesGrid.height, appsTop: allAppsHeader.y, controls: categoryControls.height})");
 check("catalog populated", "allAppsGrid.count > 0");
 check("list fits viewport", "allAppsGrid.cellWidth <= allAppsGrid.width");
 check("recent files disabled", "rootModel.showRecentDocs === false");
 check("recent app preference preserved", "Plasmoid.configuration.showRecentApps === false");
 auto popupWindow = qobject_cast<QQuickWindow*>(popup);
 if (popupWindow) popupWindow->grabWindow().save(output + "/list.png");
 auto clickButton = [&](const char *name) {
   auto button = popup->findChild<QQuickItem*>(name);
   if (!button || !popupWindow) std::exit(9);
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
 check("inner grid stays fixed", "allAppsGrid.contentY === 0");
 eval("root.scrollToLetter('S')"); QTest::qWait(260);
 check("alphabet scroll moves page", "mainFlick.contentY > 200 && allAppsGrid.contentY === 0");
 eval("mainFlick.contentY = 0"); QTest::qWait(100);
 clickButton("appsListButton");
 check("list selected", "Plasmoid.configuration.allAppsViewMode === 0 && allAppsGrid.columnsCount === 1");
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
 popup->setProperty("visible", false);
 qInfo() << "FAILURES" << failures;
 return failures ? 7 : 0;
}
