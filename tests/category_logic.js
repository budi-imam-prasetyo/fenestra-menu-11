// Exercise the actual QML category functions against small Kicker-like models.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const qml = fs.readFileSync('contents/ui/MenuRepresentation.qml', 'utf8');
function getFunction(name) {
  const match = qml.match(new RegExp(`function ${name}\\([^)]*\\) \\{`));
  assert(match, `${name} exists`);
  const start = match.index;
  let depth = 0;
  for (let i = qml.indexOf('{', start); i < qml.length; i++) {
    if (qml[i] === '{') depth++;
    if (qml[i] === '}' && --depth === 0) return qml.slice(start, i + 1);
    // The functions under test have no braces embedded in strings or comments.
  }
  throw Error(`Unbalanced ${name}`);
}
function model(rows, children = {}) {
  return {
    description: '',
    rowCount: () => rows.length,
    index: row => ({ row }),
    data: (idx, role) => rows[idx.row][role] || '',
    modelForRow: row => children[row] || null,
  };
}
function list() {
  const rows = [];
  return { rows, get count() { return rows.length; }, clear() { rows.length = 0; }, append: row => rows.push(row) };
}
const GAME = { 0: 'Game', 259: 'game.desktop', 1: 'game-icon' };
const WORK = { 0: 'Work', 259: 'work.desktop', 1: 'work-icon' };
const nested = model([{ 0: 'Subgroup' }], { 0: model([GAME, GAME, WORK]) });
const root = model([{ 0: 'Games' }, { 0: 'Office' }, { 0: 'Empty' }], {
  0: nested,
  1: model([WORK]),
  2: model([]),
});
const categoryAppsModel = list();
const allAppsComboModel = list();
const env = {
  Qt: { DisplayRole: 0 },
  i18n: s => s,
  String, Object, Math,
  kickerDisplayRole: 0, kickerDecorationRole: 1,
  kickerFavoriteIdRole: 259, kickerDescriptionRole: 257, kickerUrlRole: 266,
  categoryRootModel: root,
  sortedAppsModel: Object.assign(model([GAME, WORK]), { sourceModel: true }),
  categoryAppsModel, allAppsComboModel,
  activeCategoryRow: -1, activeCategoryName: '',
  availableCategories: [], categoryMembership: {},
  allAppsGrid: { currentIndex: 5 },
  mainFlick: { contentY: 80 }, allAppsHeader: { y: 40 },
};
env.rootItem = env;
vm.createContext(env);
for (const name of ['collectCategoryApps', 'refreshAvailableCategories', 'rebuildSelectedCategory', 'selectCategory']) {
  env[name] = vm.runInContext(`(${getFunction(name)})`, env);
}
const unique = [];
env.collectCategoryApps(nested, unique, {});
assert.equal(unique.length, 2, 'nested and duplicate membership deduplicated');
env.refreshAvailableCategories();
assert.equal(env.availableCategories.map(x => x.label).join(','), 'All apps,Games,Office', 'empty category omitted');
env.selectCategory(0);
assert.equal(categoryAppsModel.rows.map(x => x.favoriteId).join(','), 'game.desktop,work.desktop');
assert.equal(env.allAppsGrid.currentIndex, -1);
assert.equal(env.mainFlick.contentY, 40);
env.selectCategory(1);
assert.equal(categoryAppsModel.rows.map(x => x.favoriteId).join(','), 'work.desktop', 'multi-category membership');
assert.equal(categoryAppsModel.rows[0].sourceRow, 1, 'launch row retained');
// Catalog row order changes; selection follows label.
root.modelForRow = row => [model([WORK]), nested, model([])][row];
root.data = (idx) => ['Office', 'Games', 'Empty'][idx.row];
env.refreshAvailableCategories();
assert.equal(env.activeCategoryRow, 0);
assert.equal(categoryAppsModel.rows.map(x => x.favoriteId).join(','), 'work.desktop');
root.rowCount = () => 0;
env.refreshAvailableCategories();
assert.equal(env.activeCategoryRow, -1, 'removed category resets to All apps');
env.selectCategory(0);
assert.equal(categoryAppsModel.count, 0, 'empty results have a clean model');
console.log('Category model tests passed');
