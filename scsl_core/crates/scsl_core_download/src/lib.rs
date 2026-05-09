use scsl_core_domain::{CoreError, ServerInstance};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DownloadTarget {
    pub url: String,
    pub sha1: Option<String>,
    pub file_name: String,
    pub headers: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JavaVersion {
    pub component: String,
    pub major_version: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResourceType {
    Mod,
    Datapack,
    Shader,
    Resourcepack,
}

impl ResourceType {
    pub fn parse(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "mod" => Some(Self::Mod),
            "datapack" => Some(Self::Datapack),
            "shader" => Some(Self::Shader),
            "resourcepack" => Some(Self::Resourcepack),
            _ => None,
        }
    }

    pub fn directory_name(self, file_name: &str) -> &'static str {
        match self {
            Self::Mod => "mods",
            Self::Datapack => {
                if file_name.to_ascii_lowercase().ends_with(".jar") {
                    "mods"
                } else {
                    "datapacks"
                }
            }
            Self::Shader => "shaderpacks",
            Self::Resourcepack => {
                if file_name.to_ascii_lowercase().ends_with(".jar") {
                    "mods"
                } else {
                    "resourcepacks"
                }
            }
        }
    }
}

pub struct ServerDownloadPlanner {
    working_path: PathBuf,
}

impl ServerDownloadPlanner {
    pub fn new(working_path: impl Into<PathBuf>) -> Self {
        Self {
            working_path: working_path.into(),
        }
    }

    pub fn server_dir(&self, server: &ServerInstance) -> PathBuf {
        self.working_path
            .join("servers")
            .join(&server.directory_name)
    }

    pub fn server_jar_path(&self, server: &ServerInstance) -> PathBuf {
        self.server_dir(server).join(&server.server_jar)
    }

    pub fn verify_local_jar_integrity(&self, server: &ServerInstance) -> bool {
        verify_local_jar_integrity(
            self.server_jar_path(server),
            if server.java_path.trim().is_empty() {
                "java"
            } else {
                server.java_path.trim()
            },
        )
    }
}

pub struct ResourceDownloadPlanner {
    working_path: PathBuf,
}

impl ResourceDownloadPlanner {
    pub fn new(working_path: impl Into<PathBuf>) -> Self {
        Self {
            working_path: working_path.into(),
        }
    }

    pub fn resource_destination(
        &self,
        game_name: &str,
        resource_type: ResourceType,
        file_name: &str,
    ) -> Result<PathBuf, CoreError> {
        let game_name = game_name.trim();
        let file_name = file_name.trim();
        if game_name.is_empty() {
            return Err(CoreError::validation("game name cannot be empty"));
        }
        if file_name.is_empty() {
            return Err(CoreError::validation("resource file name cannot be empty"));
        }

        Ok(self
            .working_path
            .join("profiles")
            .join(game_name)
            .join(resource_type.directory_name(file_name))
            .join(file_name))
    }

    pub fn download_resource(
        &self,
        game_name: &str,
        resource_type: ResourceType,
        target: &DownloadTarget,
    ) -> Result<PathBuf, CoreError> {
        let destination = self.resource_destination(game_name, resource_type, &target.file_name)?;
        download_file_to_path(
            &target.url,
            &destination,
            target.sha1.as_deref(),
            Some(&target.headers),
        )
    }
}

pub fn verify_local_jar_integrity(jar_path: impl AsRef<Path>, java_path: &str) -> bool {
    let jar_path = jar_path.as_ref();
    if !jar_path.exists() {
        return false;
    }

    let output = Command::new(java_path)
        .arg("-jar")
        .arg(jar_path)
        .arg("--help")
        .output();
    let Ok(output) = output else {
        return false;
    };

    let merged = format!(
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    !merged.to_lowercase().contains("invalid or corrupt jarfile")
}

pub fn mirror_direct_target(
    file_name: impl Into<String>,
    download_url: impl Into<String>,
) -> Result<DownloadTarget, CoreError> {
    let file_name = file_name.into();
    let download_url = download_url.into();
    if file_name.trim().is_empty() {
        return Err(CoreError::validation("download file name cannot be empty"));
    }
    if !is_http_url(&download_url) {
        return Err(CoreError::validation("invalid download url"));
    }
    Ok(DownloadTarget {
        url: download_url,
        sha1: None,
        file_name,
        headers: BTreeMap::new(),
    })
}

pub fn forge_installer_target(
    game_version: impl AsRef<str>,
    loader_version: impl AsRef<str>,
) -> Result<DownloadTarget, CoreError> {
    let game_version = game_version.as_ref().trim();
    let loader_version = loader_version.as_ref().trim();
    if game_version.is_empty() {
        return Err(CoreError::validation("game version cannot be empty"));
    }
    if loader_version.is_empty() {
        return Err(CoreError::validation(
            "forge loader version cannot be empty",
        ));
    }

    let file_name = format!("forge-{game_version}-{loader_version}-installer.jar");
    Ok(DownloadTarget {
        url: format!(
            "https://maven.minecraftforge.net/net/minecraftforge/forge/{game_version}-{loader_version}/{file_name}"
        ),
        sha1: None,
        file_name,
        headers: BTreeMap::new(),
    })
}

pub fn fabric_server_jar_target(
    game_version: impl AsRef<str>,
    loader_version: impl AsRef<str>,
    installer_version: impl AsRef<str>,
) -> Result<DownloadTarget, CoreError> {
    let game_version = game_version.as_ref().trim();
    let loader_version = loader_version.as_ref().trim();
    let installer_version = installer_version.as_ref().trim();
    if game_version.is_empty() {
        return Err(CoreError::validation("game version cannot be empty"));
    }
    if loader_version.is_empty() {
        return Err(CoreError::validation(
            "fabric loader version cannot be empty",
        ));
    }
    if installer_version.is_empty() {
        return Err(CoreError::validation(
            "fabric installer version cannot be empty",
        ));
    }

    Ok(DownloadTarget {
        url: format!(
            "https://meta.fabricmc.net/v2/versions/loader/{game_version}/{loader_version}/{installer_version}/server/jar"
        ),
        sha1: None,
        file_name: format!("fabric-server-{game_version}-{loader_version}.jar"),
        headers: BTreeMap::new(),
    })
}

pub fn java_component_for_major(major_version: u32) -> Option<&'static str> {
    match major_version {
        8 => Some("java-runtime-alpha"),
        16 => Some("java-runtime-gamma"),
        17 => Some("java-runtime-beta"),
        21 => Some("java-runtime-delta"),
        25 => Some("java-runtime-epsilon"),
        _ => None,
    }
}

fn is_http_url(value: &str) -> bool {
    value.starts_with("https://") || value.starts_with("http://")
}

pub fn download_file_to_path(
    url: &str,
    destination: impl AsRef<Path>,
    expected_sha1: Option<&str>,
    headers: Option<&BTreeMap<String, String>>,
) -> Result<PathBuf, CoreError> {
    if !is_http_url(url) {
        return Err(CoreError::validation("invalid download url"));
    }

    let destination = destination.as_ref();
    let parent = destination.parent().ok_or_else(|| {
        CoreError::validation("download destination must have a parent directory")
    })?;
    fs::create_dir_all(parent).map_err(|error| {
        CoreError::runtime(format!("failed to create resource directory: {error}"))
    })?;

    let temp_path = destination.with_extension(format!(
        "{}.download",
        destination
            .extension()
            .and_then(|ext| ext.to_str())
            .unwrap_or_default()
    ));
    if temp_path.exists() {
        let _ = fs::remove_file(&temp_path);
    }

    let mut command = Command::new("curl");
    command
        .arg("-L")
        .arg("--fail")
        .arg("--silent")
        .arg("--show-error")
        .arg("--output")
        .arg(&temp_path);
    if let Some(headers) = headers {
        for (name, value) in headers {
            command.arg("-H").arg(format!("{name}: {value}"));
        }
    }
    let output = command
        .arg(url)
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to spawn curl: {error}")))?;
    if !output.status.success() {
        return Err(CoreError::runtime(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }

    if let Some(expected_sha1) = expected_sha1.filter(|value| !value.trim().is_empty()) {
        let actual = compute_sha1(&temp_path)?;
        if !actual.eq_ignore_ascii_case(expected_sha1.trim()) {
            let _ = fs::remove_file(&temp_path);
            return Err(CoreError::runtime(format!(
                "sha1 mismatch: expected {expected_sha1}, got {actual}"
            )));
        }
    }

    if destination.exists() {
        let _ = fs::remove_file(destination);
    }
    fs::rename(&temp_path, destination).map_err(|error| {
        CoreError::runtime(format!("failed to persist downloaded resource: {error}"))
    })?;
    Ok(destination.to_path_buf())
}

fn compute_sha1(path: impl AsRef<Path>) -> Result<String, CoreError> {
    let output = Command::new("shasum")
        .arg("-a")
        .arg("1")
        .arg(path.as_ref())
        .output()
        .map_err(|error| CoreError::runtime(format!("failed to compute sha1: {error}")))?;
    if !output.status.success() {
        return Err(CoreError::runtime(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let sha1 = stdout
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .to_string();
    if sha1.is_empty() {
        return Err(CoreError::runtime("sha1 command returned empty output"));
    }
    Ok(sha1)
}

#[cfg(test)]
mod tests {
    use super::{
        ResourceDownloadPlanner, ResourceType, fabric_server_jar_target, forge_installer_target,
        java_component_for_major, mirror_direct_target,
    };
    use std::path::PathBuf;

    #[test]
    fn builds_mirror_direct_target() {
        let target = mirror_direct_target("server.jar", "https://example.com/server.jar")
            .expect("target should build");

        assert_eq!(target.file_name, "server.jar");
        assert_eq!(target.url, "https://example.com/server.jar");
        assert!(target.sha1.is_none());
    }

    #[test]
    fn rejects_invalid_mirror_direct_target() {
        assert!(mirror_direct_target("", "https://example.com/server.jar").is_err());
        assert!(mirror_direct_target("server.jar", "not-a-url").is_err());
    }

    #[test]
    fn builds_forge_installer_target() {
        let target = forge_installer_target("1.20.1", "47.4.0").expect("target should build");

        assert_eq!(target.file_name, "forge-1.20.1-47.4.0-installer.jar");
        assert_eq!(
            target.url,
            "https://maven.minecraftforge.net/net/minecraftforge/forge/1.20.1-47.4.0/forge-1.20.1-47.4.0-installer.jar"
        );
    }

    #[test]
    fn builds_fabric_server_jar_target() {
        let target =
            fabric_server_jar_target("1.21.1", "0.16.10", "1.0.1").expect("target should build");

        assert_eq!(target.file_name, "fabric-server-1.21.1-0.16.10.jar");
        assert_eq!(
            target.url,
            "https://meta.fabricmc.net/v2/versions/loader/1.21.1/0.16.10/1.0.1/server/jar"
        );
    }

    #[test]
    fn maps_java_components() {
        assert_eq!(java_component_for_major(21), Some("java-runtime-delta"));
        assert_eq!(java_component_for_major(25), Some("java-runtime-epsilon"));
        assert_eq!(java_component_for_major(99), None);
    }

    #[test]
    fn resolves_mod_resource_destination() {
        let planner = ResourceDownloadPlanner::new("/tmp/scsl");
        let path = planner
            .resource_destination("Demo", ResourceType::Mod, "fabric-api.jar")
            .expect("path should resolve");

        assert_eq!(
            path,
            PathBuf::from("/tmp/scsl/profiles/Demo/mods/fabric-api.jar")
        );
    }

    #[test]
    fn routes_resourcepack_jars_to_mods_like_swift_app() {
        let planner = ResourceDownloadPlanner::new("/tmp/scsl");
        let path = planner
            .resource_destination("Demo", ResourceType::Resourcepack, "optifine.jar")
            .expect("path should resolve");

        assert_eq!(
            path,
            PathBuf::from("/tmp/scsl/profiles/Demo/mods/optifine.jar")
        );
    }
}
