use scsl_core_domain::{CoreError, ServerType};

pub const FASTMIRROR_DEFAULT_BASE_URL: &str = "https://download.fastmirror.net/api/v3";
pub const POLARS_DEFAULT_BASE_URL: &str = "https://mirror.polars.cc/api/query/minecraft/core";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ServerMirrorSource {
    Official,
    FastMirror,
    Polars,
    Custom,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FastMirrorCoreSummary {
    pub name: String,
    pub tag: Option<String>,
    pub recommend: bool,
    pub homepage: Option<String>,
    pub mc_versions: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FastMirrorCoreDetail {
    pub name: String,
    pub mc_version: String,
    pub core_version: String,
    pub update_time: Option<String>,
    pub sha1: Option<String>,
    pub filename: String,
    pub download_url: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PolarsCoreType {
    pub id: i64,
    pub name: String,
    pub description: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PolarsCoreItem {
    pub name: String,
    pub download_url: String,
}

impl PolarsCoreItem {
    pub fn new(name: impl Into<String>, download_url: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            download_url: normalize_polars_download_url(&download_url.into()),
        }
    }
}

pub fn fastmirror_core_name(server_type: ServerType) -> &'static str {
    match server_type {
        ServerType::Vanilla => "Vanilla",
        ServerType::Paper => "Paper",
        ServerType::Fabric => "Fabric",
        ServerType::Forge => "Forge",
        ServerType::Custom => "Custom",
    }
}

pub fn fastmirror_server_type(core_name: &str) -> Option<ServerType> {
    match core_name.to_lowercase().as_str() {
        "vanilla" => Some(ServerType::Vanilla),
        "paper" => Some(ServerType::Paper),
        "fabric" => Some(ServerType::Fabric),
        "forge" => Some(ServerType::Forge),
        _ => None,
    }
}

pub fn normalize_fastmirror_base_url(value: Option<&str>) -> String {
    let raw = value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(FASTMIRROR_DEFAULT_BASE_URL);
    let trimmed = raw.trim_end_matches('/');
    if trimmed.to_lowercase().contains("/api/v3") {
        trimmed.to_string()
    } else {
        format!("{trimmed}/api/v3")
    }
}

pub fn fastmirror_core_detail_url(
    base_url: Option<&str>,
    core_name: &str,
    game_version: &str,
    core_version: &str,
) -> String {
    format!(
        "{}/{}/{}/{}",
        normalize_fastmirror_base_url(base_url),
        core_name,
        game_version,
        core_version
    )
}

pub fn polars_core_items_url(base_url: Option<&str>, core_type_id: i64) -> String {
    format!(
        "{}/{}",
        normalize_polars_base_url(base_url).trim_end_matches('/'),
        core_type_id
    )
}

pub fn normalize_polars_base_url(value: Option<&str>) -> String {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(POLARS_DEFAULT_BASE_URL)
        .trim_end_matches('/')
        .to_string()
}

pub fn normalize_polars_download_url(value: &str) -> String {
    let trimmed = value.trim();
    if let Some(rest) = trimmed.strip_prefix("http://") {
        format!("https://{rest}")
    } else {
        trimmed.to_string()
    }
}

pub fn custom_mirror_url(
    base_url: &str,
    template: &str,
    core: &str,
    game_version: &str,
    core_version: &str,
) -> Result<String, CoreError> {
    let mut resolved = template.to_string();
    resolved = resolved.replace("{core}", core);
    resolved = resolved.replace("{mc_version}", game_version);
    resolved = resolved.replace("{core_version}", core_version);

    let lower = resolved.to_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        return Ok(resolved);
    }

    let trimmed_path = resolved.trim_start_matches('/');
    if trimmed_path.is_empty() {
        return Err(CoreError::validation("custom mirror path cannot be empty"));
    }

    let base = base_url.trim_end_matches('/');
    if base.is_empty() {
        return Err(CoreError::validation(
            "custom mirror base url cannot be empty",
        ));
    }
    Ok(format!("{base}/{trimmed_path}"))
}

pub fn unique_strings<I>(values: I) -> Vec<String>
where
    I: IntoIterator<Item = String>,
{
    let mut seen = Vec::new();
    for value in values {
        if !seen.contains(&value) {
            seen.push(value);
        }
    }
    seen
}

#[cfg(test)]
mod tests {
    use super::{
        custom_mirror_url, fastmirror_core_detail_url, fastmirror_core_name,
        fastmirror_server_type, normalize_fastmirror_base_url, normalize_polars_download_url,
        polars_core_items_url, unique_strings,
    };
    use scsl_core_domain::ServerType;

    #[test]
    fn maps_fastmirror_core_names() {
        assert_eq!(fastmirror_core_name(ServerType::Paper), "Paper");
        assert_eq!(fastmirror_server_type("forge"), Some(ServerType::Forge));
        assert_eq!(fastmirror_server_type("custom"), None);
    }

    #[test]
    fn normalizes_fastmirror_base_url() {
        assert_eq!(
            normalize_fastmirror_base_url(Some("https://mirror.example")),
            "https://mirror.example/api/v3"
        );
        assert_eq!(
            normalize_fastmirror_base_url(Some("https://mirror.example/api/v3/")),
            "https://mirror.example/api/v3"
        );
    }

    #[test]
    fn builds_fastmirror_detail_url() {
        assert_eq!(
            fastmirror_core_detail_url(Some("https://mirror.example"), "Paper", "1.21.1", "123"),
            "https://mirror.example/api/v3/Paper/1.21.1/123"
        );
    }

    #[test]
    fn normalizes_polars_urls() {
        assert_eq!(
            normalize_polars_download_url("http://example.com/server.jar"),
            "https://example.com/server.jar"
        );
        assert_eq!(
            polars_core_items_url(Some("https://mirror.example/root/"), 42),
            "https://mirror.example/root/42"
        );
    }

    #[test]
    fn builds_custom_mirror_urls() {
        assert_eq!(
            custom_mirror_url(
                "https://mirror.example/api",
                "/cores/{core}/{mc_version}/{core_version}",
                "Paper",
                "1.21.1",
                "123"
            )
            .expect("url should build"),
            "https://mirror.example/api/cores/Paper/1.21.1/123"
        );
        assert_eq!(
            custom_mirror_url(
                "https://mirror.example/api",
                "https://cdn.example/{core}.jar",
                "Paper",
                "1.21.1",
                "123"
            )
            .expect("url should build"),
            "https://cdn.example/Paper.jar"
        );
    }

    #[test]
    fn keeps_unique_strings_in_order() {
        assert_eq!(
            unique_strings(["a".to_string(), "b".to_string(), "a".to_string()]),
            vec!["a".to_string(), "b".to_string()]
        );
    }
}
