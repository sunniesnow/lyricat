# Lyricat

Lyricat is an online service that provides querying service for things related to the game Lyrica.

## Deploy

Follow the steps.

1. Clone this repo and run `bundle install`.
2. Use [AssetRipper](https://github.com/AssetRipper/AssetRipper)
to extract [Lyrica's APK](https://apkcombo.com/lyrica/com.Rnova.lyrica/download/apk).
Specify the paths to useful files in `config.yml`
or copy the useful files to the paths specified in `config.yml`.
3. Register a test account in Lyrica. [Get its session token](#get-session-token) and
store it in the environment variable `LYRICAT_STATIC_SESSION_TOKEN`.
4. Run `rackup -p 8013` to start the server.
Change `8013` to the port you like.
5. Optionally, set up reverse proxy and SSL etc.

## API

All APIs is invoked using `POST` method.

Note that when mentioning `diff_id`, refer to this table:

| `diff_id` | difficulty name |
|-|-|
| 1 | Easy |
| 2 | Normal |
| 3 | Hard |
| 4 | Master |
| 5 | Special |

### Dynamic API

Under `/dynamic/`,
such as `/dynamic/user`, `dynamic/b35`, etc.
Provide session token and options in the format `{"session_token":, "options":}` as a JSON in the request body.
The `options` must be an object, or omitted to be `{}`.

#### `user`

Get user information.

Options: none.

Output sample:

```json
{
  "username": "something@example.com",
  "created_at": "2019-01-01T00:00:00.000Z",
  "nickname": "some nickname",
  "head": 42 // head id
}
```

#### `b35`

Options: none.

Output sample:

```json
[
  {
    "song_id": 115,
    "diff_id": 5,
    "score": 1000000,
    "mr": 15
  },
  ... // totally 35 items at most
]
```

#### `b15`

Options: none.

Output sample:

```json
[
  {
    "song_id": 226,
    "diff_id": 4,
    "score": 1000000,
    "mr": 12.5
  },
  ... // totally 15 items at most
]
```

#### `b50`

First b35, then b15.

Options: none.

Output sample:

```json
[
  {
    "song_id": 115,
    "diff_id": 5,
    "score": 1000000,
    "mr": 15
  },
  ... // totally 50 items at most
]
```

#### `mr`

Options:

- `details`: an array of any subset of `"b35"`, `"b15"`, and `"b50"`.
  If omitted, defaults to `[]`.
  Specifies which details to show.

Output sample:

```json
{
	"mr": 11.358172,
	"b15": [ ... ], // if "b15" is in `details`
	"b35": [ ... ], // if "b35" is in `details`
	"b50": [ ... ] // if "b50" is in `details`
}
```

#### `leaderboard`

Gets the rank and score for a single chart.

Options:

- `song_id`.
- `diff_id`.

Output sample:

```json
{
  "score": 1000000,
  "rank": 1,
  "diff_id": 5,
  "song_id": 115
}
```

#### `month_leaderboard`

Gets the rank and score for a single chart in the current month.

Options:

- `song_id`.
- `diff_id`.

Output sample:

```json
{
  "score": 1000000,
  "rank": 1,
  "diff_id": 5,
  "song_id": 115
}
```

#### `song`

Gets basic song information and the best score for each difficulty (chart).

Options:

- `song_id`.

Output sample:

```json
{
  "song_id": 115,
  "name": "Butterfly Dance",
  "singer": "XinG",
  "writer": null,
  "diff": {
    "1": 3.5,
    "2": 6,
    "3": 9.6,
    "4": 12.9,
    "5": 13
  },
  "scores": {
    "5": 1000000,
    "1": 0,
    "4": 1000000,
    "3": 998606,
    "2": 998688
  },
  "mrs": {
    "5": 15,
    "1": 0,
    "4": 14.9,
    "3": 11.5303,
    "2": 7.9344
  }
}
```

### Static API

Under `/static/`,
such as `/static/song`, `static/leaderboard`, etc.
Provide options directly in a JSON object in the request body.
No need for a session token.

#### `leaderboard`

Options:

- `song_id`.
- `diff_id`.

Output sample:

```json
[
  {
    "score": 1000000,
    "nickname": "chaos",
    "head": 1028,
    "rank": 1
  },
  ... // totally 50 items at most
]
```

#### `month_leaderboard`

Options:

- `song_id`.
- `diff_id`.

#### `song`

Detailed song info.

Options:

- `song_id`.
- `fields`: An array of any subset of `song_id name singer writer diff label origin update_version year lyrics lyrics_b` (each word is a string).
Defaults to be `song_id name singer writer diff label origin update_version year`. Specifies which fields to show in the response.
- `diff_format`: One of `"in_game"`, `"precise"`, `"in_game_and_precise"`, or `"in_game_and_abbr_precise"`.
Default: `"in_game_and_abbr_precise"`.
- `diff_name_format`: One of `"id"`, `"in_game"`, or `"field"`.
Default: `"in_game"`.
- `lang`: One of `"tw"`, `"cn"`, `"jp"`, or `"eng"`.
Default: `"tw"`.

Output sample:

```json
{
  "song_id": 215,
  "name": "獵行歌",
  "singer": "武柳先生",
  "writer": "詞 武柳先生\n曲 白蘋",
  "diff": {
    "簡單": "三(.0)",
    "普通": "六(.0)",
    "困難": "九上(.6)",
    "宗師": "廿(.2)"
  },
  "label": "戰",
  "origin": "〈唐〉盧綸《和張僕射塞下曲・其一、二、三》",
  "update_version": "4.0~4.9",
  "year": 2023
}
```

## Get session token

On Android, look at `/storage/emulated/0/Android/data/com.Rnova.lyrica/files/Parse.settings`.
Or, on any devices, capture HTTP requests and look at the `X-Parse-Session-Token` header made towards `https://lyrica-main-2.herokuapp.com`.

## License

This is **not** free software.
See LICENSE for details.
