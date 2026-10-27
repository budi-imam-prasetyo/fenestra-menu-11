use cxx_qt_build::{CxxQtBuilder, PluginType, QmlModule};

fn main() {
    // The plugin is assembled by rust/CMakeLists.txt as an explicit MODULE
    // target that links this staticlib. It must nevertheless be a *dynamic*
    // Qt plugin: with the default static plugin type Qt compiles
    // `qt_plugin_instance` with internal linkage, so the wrapper library has
    // no exported entry point and the QML engine refuses to load it.
    CxxQtBuilder::new_qml_module(
        QmlModule::new("org.fenestra.menu11.core")
            .version(1, 0)
            .plugin_type(PluginType::Dynamic),
    )
    .files(["src/lib.rs"])
    .build();
}
