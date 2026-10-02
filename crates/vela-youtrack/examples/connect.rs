use std::env;

use vela_youtrack::Client;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let service_url =
        env::var("YOUTRACK_URL").expect("set YOUTRACK_URL to the YouTrack service URL");
    let client = match env::var("YOUTRACK_TOKEN") {
        Ok(token) if !token.is_empty() => Client::new(&service_url, token)?,
        Ok(_) | Err(env::VarError::NotPresent) => Client::guest(&service_url)?,
        Err(error) => return Err(error.into()),
    };
    let user = client.current_user().await?;

    println!("Connected as {} ({})", user.full_name, user.login);

    for issue in client.issues(Some("for: me #Unresolved"), 20).await? {
        println!("{}  {}", issue.id_readable, issue.summary);
    }

    Ok(())
}
