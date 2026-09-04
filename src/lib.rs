use zed_extension_api as zed;

mod ctags_lsp;

struct CtagsExtension {}

impl zed::Extension for CtagsExtension {
    fn new() -> Self {
        Self {}
    }

    fn language_server_command(
        &mut self,
        language_server_id: &zed_extension_api::LanguageServerId,
        worktree: &zed_extension_api::Worktree,
    ) -> zed_extension_api::Result<zed_extension_api::Command> {
        let command = ctags_lsp::get_ctags_lsp_binary_path();
        if std::fs::metadata(&command).is_err() {
            let err_msg = format!(
                "ctags-lsp binary not found at {}; reinstall zed-ctags-lsp-local or run install.ps1",
                command
            );
            zed::set_language_server_installation_status(
                language_server_id,
                &zed::LanguageServerInstallationStatus::Failed(err_msg.clone()),
            );
            return Err(err_msg);
        }

        zed::set_language_server_installation_status(
            language_server_id,
            &zed::LanguageServerInstallationStatus::None,
        );

        Ok(zed::Command {
            command,
            args: ctags_lsp::get_ctags_lsp_args(worktree),
            env: vec![],
        })
    }
}

zed::register_extension!(CtagsExtension);
