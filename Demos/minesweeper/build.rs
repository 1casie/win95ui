fn main() {
    // Link against the Swift Win95 dylib built by `swift build`.
    // PROFILE-aware so both `cargo build` and `cargo build --release`
    // find the matching Swift products (requires the same -c flag there).
    let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let profile = std::env::var("PROFILE").unwrap_or_else(|_| "debug".into());
    let lib = std::path::Path::new(&manifest).join(format!("../../.build/{profile}"));
    println!("cargo:rustc-link-search=native={}", lib.display());
    println!("cargo:rustc-link-lib=dylib=Win95");
    // So the binary finds it at runtime without install_name surgery.
    println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lib.display());
}
