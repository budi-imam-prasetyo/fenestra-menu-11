/*
 * Fenestra Menu 11 — https://github.com/naykkalak/fenestra-menu-11
 * Part of Fenestra Menu 11 (naykkalak, 2026), a fork of Menu 11 Next by Eisteed,
 * itself based on Menu 11 / Ditto Menu by adhe (GPL-2.0-or-later).
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
.pragma library

// Fenestra Menu 11 — Plugin Registry
//
// Plugin contract:
//   {
//     name:         String         — display name
//     icon:         String         — icon name
//     commands:     Array          — palette commands [{name,icon,desc,cmd}]
//     handleQuery:  fn(q) → obj|null   — command palette override (e.g. /calc)
//     searchResults: fn(q) → [{icon,title,subtitle,action}]  — search page results
//     uiSection:    Component|null — QML Component for a home-page section
//   }
//
// Register via: PluginSystem.register({ … })

var _registry = [];

function register(plugin) {
    _registry.push(plugin);
}

function registeredPlugins() {
    return _registry.slice();
}

// Palette commands contributed by all plugins
function extraCommands() {
    var result = [];
    for (var i = 0; i < _registry.length; i++) {
        var p = _registry[i];
        if (Array.isArray(p.commands)) {
            for (var j = 0; j < p.commands.length; j++) {
                result.push(p.commands[j]);
            }
        }
    }
    return result;
}

// First non-null result from any plugin's handleQuery, or null
function handleQuery(query) {
    for (var i = 0; i < _registry.length; i++) {
        var p = _registry[i];
        if (typeof p.handleQuery === "function") {
            var r = p.handleQuery(query);
            if (r !== null && r !== undefined) return r;
        }
    }
    return null;
}

// Aggregated search results from all plugins for a given query
// Each result: { icon, title, subtitle, action }
//   action is either a shell command string or a JS function (called with no args)
function searchResults(query) {
    if (!query || query.length < 2) return [];
    var results = [];
    for (var i = 0; i < _registry.length; i++) {
        var p = _registry[i];
        if (typeof p.searchResults === "function") {
            try {
                var items = p.searchResults(query);
                if (Array.isArray(items)) {
                    for (var j = 0; j < items.length; j++) {
                        results.push(items[j]);
                    }
                }
            } catch(e) { /* isolate bad plugins */ }
        }
    }
    return results;
}

// UI sections contributed by plugins (array of { name, component } objects)
function uiSections() {
    var result = [];
    for (var i = 0; i < _registry.length; i++) {
        var p = _registry[i];
        if (p.uiSection && p.uiSection !== null) {
            result.push({ name: p.name, component: p.uiSection });
        }
    }
    return result;
}
