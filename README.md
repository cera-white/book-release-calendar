# Book Release Calendar

The goal of this project is to generate a calendar of book releases that can be subscribed to via Google Calendar (or another calendar app of your choice).

## How to Use

Configure which book series to track in `config.yaml`.

Config format:
```yaml
series:
  - title: "Book Title"
    type: manga, manhwa, ...
    format: paperback, ebook, ...
    author: "Author Name"
    publisher: yen_press
    series_url: "https://"
    status: ongoing or complete
```

Current supported publishers are:
* Yen Press (`yen_press`)
* Seven Seas Entertainment (`seven_seas_entertainment`)
* Square Enix (`square_enix`)
* Kodansha International (`kodansha_international`)

Publishers that need parsers:
* Viz Media, LLC (`viz_media`)
* Random House Worlds (`random_house_worlds`)

Set environment variables:
```bash
export FTP_USERNAME=''
export FTP_PASSWORD=''
export FTP_HOST=''
```

The `generate` script will:
1. Parse publishers' websites to get information about past and upcoming releases.
2. Generate a file called `book-releases.ics`
3. Upload `book-releases.ics` to a web server.

```bash
ruby generate.rb
```

Calendar can be added to Google Calendar by adding a new calendar "From URL".
* Example URL: https://anigramsproductions.com/personal/calendars/book-releases.ics


## Future Enhancements

* Clean up `generate` script
    * Move FTP stuff into its own class
    * Add arguments for things like domain name, file name, etc.
    * Add arguments to run individual pieces, like to make sure .ics generates correctly before uploading
