use std::process::Command;

#[test]
fn credential_list_succeeds_before_configuration_exists() {
    let directory = tempfile::tempdir().expect("tempdir");
    let output = Command::new(env!("CARGO_BIN_EXE_model-gateway"))
        .args(["credentials", "list"])
        .env(
            "MODEL_GATEWAY_CONFIG",
            directory.path().join("missing.toml"),
        )
        .env("MODEL_GATEWAY_SECRET_STORE", "environment")
        .output()
        .expect("run credentials list");
    assert!(output.status.success());
    assert_eq!(
        String::from_utf8(output.stdout).expect("stdout"),
        "No configured credentials\n"
    );
    assert!(output.stderr.is_empty());
}
