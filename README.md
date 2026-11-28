<h1 align="center">Menzen</h1>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.0--rc.3-0a84ff?style=for-the-badge" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%2014%E2%80%9326-111111?style=for-the-badge" />
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-GPLv3-blue?style=for-the-badge" /></a>
  <img alt="Language" src="https://img.shields.io/badge/language-Objective--C%20%26%20Logos-2b2b2b?style=for-the-badge" />
  <a href="https://havoc.app/package/menzen"><img src="https://img.shields.io/badge/available_on-Havoc-1757FF?style=for-the-badge" alt="Available on Havoc" /></a>
  <a href="https://crowdin.com/project/menzen"><img src="https://img.shields.io/badge/translate_on-Crowdin-2E3340?style=for-the-badge&amp;logo=crowdin" alt="Translate on Crowdin" /></a>
</p>

## About

Menzen is Discord RPC for jailbroken iPhones. It puts what you're listening to, watching or playing on your iPhone in your Discord status, the way Discord does on desktop.

It runs on iOS 14 through 26, on rootful, rootless and RootHide jailbreaks.

## Features

- Shows "Listening to" for music and podcasts, "Watching" for video and "Playing" for games, with a progress bar or a timer.
- Built-in support for Apple Music, Apple TV, Spotify, YouTube, YouTube Music, YouTube TV, TIDAL, Deezer, Amazon Music, Pandora, SoundCloud, Qobuz, Audiomack, Netflix, Disney+, HBO Max, Hulu, Prime Video, Paramount+, Peacock, Pluto TV, Tubi, Crunchyroll, Plex, Twitch and Kick. Most of them add album art or thumbnails, episode names and links back to the song or video.
- Podcasts from Apple Podcasts, Castro, Overcast, Pocket Casts and Spotify, with the episode and the show. Apple Podcasts and Spotify also add the artwork and links to the episode.
- With Other Apps turned on, anything in the Now Playing controls can show up too, with less detail. Browsers, chat apps and social networking apps are always left out.
- Shows the game on screen with its App Store icon, without touching the game itself.
- You pick what each line and picture of your activity shows, and what shows in member lists.
- Custom statuses with your own text, pictures, a timer, a party size like "(2 of 4)" and up to two link buttons. Each one can also set your Discord status, such as Idle or Do Not Disturb, while it shows.
- Your Discord status can follow Do Not Disturb and Focus on your iPhone.
- Songs can get an "Open in" button that links to the track.
- Privacy Mode shows only the app's name and icon, for every app or just the ones you pick. You can turn it on from Settings or from Control Center, where a second module handles a single app of your choice. Control Center also has a toggle to turn Menzen on and off.
- You choose which apps and games can show up, and which comes first when more than one has something to show.
- Other tweaks can show their own activity through Menzen once you allow them, and each one gets its own page where you can remove it again. Developers can find how in [docs/API.md](docs/API.md).
- You sign in on Discord's own page, on the iPhone or from another device with a code. Menzen never asks for your Discord token and keeps the sign-in in the iPhone's Keychain. If Discord stops connecting, Settings asks you to sign in again.
- The settings work inside the Settings app, TweakSettings and R3v4mp.

## Privacy

Menzen has no servers and no analytics. It only talks to Discord, to GitHub for the list of app icons, and to the apps' own services for details like artist pictures. Signing out or uninstalling Menzen removes its access to your Discord account. The full [Privacy Policy](https://menzen.waru.moe/privacy/) and [Terms of Service](https://menzen.waru.moe/tos/) are on the website.

## Localization and open source

Menzen includes English. You can help translate it into your language on [Crowdin](https://crowdin.com/project/menzen). You don't need to know how to code, and translations come with Menzen's next update. If your language isn't listed, [open an issue](https://github.com/waruhachi/Menzen/issues) and it'll be added.

Thanks to everyone who translates Menzen:

<!-- CROWDIN-CONTRIBUTORS-START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top">
        <a href="https://crowdin.com/profile/TheMightyOfTrains"><img alt="logo" style="width: 64px" src="https://crowdin-static.cf-downloads.crowdin.com/avatar/17969167/medium/cb3366e5d6fc15f8a9930668d4f923e6.jpeg" />
          <br />
          <sub><b>TheMightyOfTrains</b></sub></a>
        <br />
        <sub><b>806 words</b></sub>
        <br /><sub><b><code title="Romanian">ro</code></b></sub>
      </td>
      <td align="center" valign="top">
        <a href="https://crowdin.com/profile/meteoni"><img alt="logo" style="width: 64px" src="https://crowdin-static.cf-downloads.crowdin.com/avatar/17789157/medium/db595cc3b6a767409fd465c78753a924.jpeg" />
          <br />
          <sub><b>Meteoni-San</b></sub>
          <br />
          <sub><b>(meteoni)</b></sub></a>
        <br />
        <sub><b>748 words</b></sub>
        <br /><sub><b><code title="Chinese Simplified">zh-CN</code></b></sub>
      </td>
      <td align="center" valign="top">
        <a href="https://crowdin.com/profile/pizzasdu83"><img alt="logo" style="width: 64px" src="https://crowdin-static.cf-downloads.crowdin.com/avatar/16555353/medium/d4436f7125e8dce1c0a940abcfddc941.jpeg" />
          <br />
          <sub><b>SaaS</b></sub>
          <br />
          <sub><b>(pizzasdu83)</b></sub></a>
        <br />
        <sub><b>56 words</b></sub>
        <br /><sub><b><code title="French">fr</code></b></sub>
      </td>
    </tr>
  </tbody>
</table>
<!-- CROWDIN-CONTRIBUTORS-END -->

Menzen is open source under the [GNU GPLv3 license](LICENSE). You can explore the code, contribute improvements, or [report an issue](https://github.com/waruhachi/Menzen/issues).

## Support development

Menzen is free on [GitHub](https://github.com/waruhachi/Menzen/releases). If you'd like to support me and Menzen's development, you can buy it on [Havoc](https://havoc.app/package/menzen). **The paid and free versions will always have the same features.**

Menzen is not affiliated with or endorsed by Discord or Apple.
