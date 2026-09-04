use zed_extension_api as zed;

const CTAGS_LSP_FOLDER_NAME: &str = "ctags-lsp-project";

fn ctags_lsp_binary_name() -> &'static str {
    match zed::current_platform().0 {
        zed::Os::Windows => "ctags-lsp.exe",
        _ => "ctags-lsp",
    }
}

pub fn get_ctags_lsp_binary_path() -> String {
    format!("{}/{}", CTAGS_LSP_FOLDER_NAME, ctags_lsp_binary_name())
}

pub fn get_ctags_lsp_args(_worktree: &zed::Worktree) -> Vec<String> {
    let ctags_bin =
        std::env::var("CTAGS_BIN").unwrap_or_else(|_| match zed::current_platform().0 {
            zed::Os::Windows => "D:\\Tools\\ctags\\ctags.exe".to_string(),
            _ => "ctags".to_string(),
        });
    vec!["--ctags-bin".to_string(), ctags_bin]
}
