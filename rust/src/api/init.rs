//! 引擎全局初始化：日志与数据库引导。

use crate::library_db::init_global_db;
use flutter_rust_bridge::frb;

/// 初始化漫画引擎
///
/// 必须在调用其他接口前调用此函数。
#[frb(init)]
pub fn init_app() {
    // 初始化日志
    #[cfg(target_os = "android")]
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Info)
            .with_tag("ZephyrComics"),
    );

    #[cfg(not(target_os = "android"))]
    let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .try_init();

    // 初始化数据库 (阅读进度/书签/书架)
    if let Err(e) = init_global_db(None) {
        log::warn!("数据库初始化失败：{} (阅读进度等功能将不可用)", e);
    } else {
        log::info!("数据库初始化完成");
    }

    log::info!("漫画引擎初始化完成 (ZIP 读取 + 数据库)");
}
