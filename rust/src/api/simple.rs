#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

// 保留此函数供 FRB 兼容（实际的初始化在 api/init.rs 中）
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
