# Menzen API

Your tweak or jailbreak app can show its own activity on the user's Discord profile through Menzen. Menzen handles signing in, talking to Discord and the user's Privacy Mode. You send what to show.

Nothing shows until the user allows it. The first time your code connects, your app appears under **Settings → Menzen → Connected Apps**, switched off. It shows only once the user turns on Connected Apps and your app's switch. They can turn either off at any time. If the user has set the priority so that something else comes first (a custom activity, a game, music), that shows instead of yours.

## Setup

You need two files from Menzen: the header [`Client/Menzen.h`](../Client/Menzen.h) and `libmenzen.dylib`, which the Menzen package installs at `<jbroot>/usr/lib/libmenzen.dylib`.

1. Copy `Menzen.h` to `$THEOS/include/Menzen/Menzen.h`.
2. Copy `libmenzen.dylib` from the package to `$THEOS/lib/` (for rootless builds, `$THEOS/lib/iphone/rootless/`).
3. Link it in your Makefile:

   ```make
   MyTweak_LIBRARIES = menzen
   ```

4. Depend on Menzen in your `control` file:

   ```
   Depends: moe.waru.menzen (>= 1.0.0)
   ```

If Menzen should be optional for your package, don't link it. Load it at runtime instead, as shown under [Optional Menzen](#optional-menzen).

## Showing an activity

```objc
#import <Menzen/Menzen.h>

static MenzenClient *client;

%ctor {
	client = [[MenzenClient alloc] initWithIdentifier:@"com.example.mytweak" name:@"My Tweak"];
}

static void ShowLevel(NSString *level, NSDate *started) {
	MenzenClientActivity *activity = [MenzenClientActivity new];
	activity.type = MenzenClientActivityTypePlaying;
	activity.name = @"My Game";
	activity.details = level;
	activity.state = @"Hard mode";
	activity.largeImageURL = [NSURL URLWithString:@"https://example.com/icon.png"];
	activity.largeText = @"My Game 2.1";
	activity.startDate = started;
	client.activity = activity;
}

static void StopShowing(void) {
	client.activity = nil;
}
```

- **identifier** names your app for good. Use reverse DNS that's yours (`com.example.mytweak`): up to 128 letters, digits, dots, dashes and underscores. Users allow apps by this identifier, so changing it makes them allow you again.
- **name** is what users see in Menzen's settings, up to 64 characters. It's also the activity's heading when you leave `activity.name` empty.
- The initializer returns `nil` if either one isn't valid.

Keep the client for as long as you want to show something. Your activity is cleared when the client is deallocated or your process exits. If Menzen restarts, the client sends your activity again on its own.

`MenzenClient` is safe to use from any thread. You can set `activity` as often as you like; Menzen sends the newest one to Discord about a second later, so quick changes are merged and don't hit Discord's rate limits.

### What each field shows

| Property | On the profile |
|---|---|
| `type` | The verb: Playing, Listening to or Watching |
| `name` | The heading after the verb (your app's name when `nil`) |
| `details` | The first line |
| `state` | The second line |
| `largeImageURL` | The big picture |
| `largeText` | Shown when the big picture is hovered or tapped |
| `smallImageURL` | The badge in the corner of the big picture |
| `smallText` | Shown when the badge is hovered or tapped |
| `startDate` | Time elapsed since then |
| `endDate` | With `startDate`, a progress bar instead |
| `statusDisplay` | Which line shows next to the user's name in member lists: the name (default), details or state |

Menzen trims texts, cuts them to 128 characters and leaves out empty ones. Discord shows `largeText` and the small picture only with a big picture, so Menzen drops them without one.

Images must be public `https` links, since anyone who sees the profile can open them. Menzen leaves out links with a user name or password in them, or with a query item named like a token, key, auth, session, secret, password or signature. Discord downloads the image through its media proxy, so it has to be reachable from the internet.

When the user turns on Privacy Mode, only `type`, `name` and the big picture show.

## Knowing whether it shows

`state` tells you whether what you send shows, and `stateChangedHandler` is called on the main queue when it changes:

```objc
client.stateChangedHandler = ^(MenzenClientState state) {
	switch (state) {
		case MenzenClientStateAllowed:
			// Shows, unless something the user put first has an activity.
			break;
		case MenzenClientStateNotAllowed:
			// Listed in Menzen's settings, but the user hasn't allowed it.
			break;
		case MenzenClientStateOff:
			// Menzen or Connected Apps is off.
			break;
		case MenzenClientStateUnavailable:
			// Menzen isn't installed or can't be reached yet.
			break;
	}
};
```

You don't need to wait for `MenzenClientStateAllowed` before setting `activity`. Menzen keeps the last one you sent and shows it as soon as the user allows your app.

If more than one allowed app has an activity, the one that sent last shows.

## Sandboxed processes

Tweaks in App Store apps and in most system daemons run inside a sandbox that can't reach Menzen by default. Menzen ships a [libSandy](https://github.com/opa334/libSandy) profile for this, and `libmenzen` applies it for you before connecting. You don't need to do anything.

## Optional Menzen

To work with or without Menzen installed, load the library at runtime and look the classes up by name. Don't link `menzen` in this case, and don't add it to `Depends`.

```objc
#import <dlfcn.h>
#import <roothide.h>
#import <Menzen/Menzen.h>

static MenzenClient *client;

%ctor {
	if (!dlopen(jbroot("/usr/lib/libmenzen.dylib"), RTLD_LAZY)) return;
	Class clientClass = NSClassFromString(@"MenzenClient");
	client = [[clientClass alloc] initWithIdentifier:@"com.example.mytweak" name:@"My Tweak"];
}

static void ShowLevel(NSString *level) {
	if (!client) return;
	MenzenClientActivity *activity = [NSClassFromString(@"MenzenClientActivity") new];
	activity.details = level;
	client.activity = activity;
}
```

Here `<roothide.h>` provides `jbroot()`, which finds the library on rootful, rootless and RootHide jailbreaks.

## Versions

`MENZEN_API_VERSION` in the header is 1. Later versions will only add to the API, so code written against this one keeps working.
