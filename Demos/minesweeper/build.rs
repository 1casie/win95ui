fn main() {
    // Link against the Swift Win95 dylib built by `swift build`.
    let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    let lib = std::path::Path::new(&manifest).join("../../.build/debug");
    println!("cargo:rustc-link-search=native={}", lib.display());
    println!("cargo:rustc-link-lib=dylib=Win95");
    // So the binary finds it at runtime without install_name surgery.
    println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lib.display());
}
