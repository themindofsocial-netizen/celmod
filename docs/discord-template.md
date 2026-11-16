# |CelMod| Discord Server Template

A ready-to-copy layout for the CelMod Discord. Build it once by hand (about 15 minutes), then turn it into a
real Discord template: **Server Settings → Server Template → Generate Template**. That gives you a
`discord.new/...` link that recreates the whole layout, roles and permissions in one click.

---

## 1. Roles

Create them in this order (top = highest). Colours match the website's palette.

| Role | Colour | Who gets it | Key permissions |
|---|---|---|---|
| **Owner** | `#FFB200` gold | You | Administrator |
| **Admin** | `#FF2200` red | In-game admins | Manage Messages, Kick, Ban, Timeout, Manage Threads, Mention @everyone |
| **Moderator** | `#AACC22` olive | Chat moderators | Manage Messages, Timeout, Manage Threads |
| **Event Host** | `#9CCCFF` blue | Players who run events (mazes, parkour, builds) | Mention @Events, Manage Events, Priority Speaker in voice |
| **Builder** | `#71E100` green | Regular players (give after they join the game server) | Attach Files, Embed Links, Add Reactions, Use External Emoji, Stream |
| **Collector** | `#FFCD5B` light gold | Optional flair: owns a rare emblem (Black, White, Phantom...) | none extra |
| **Events** | none | Pings for events (self-assign) | none |
| **Updates** | none | Pings for new updates (self-assign) | none |
| **Bots** | `#AAAA88` grey | Bots and webhooks | Send Messages, Embed Links |
| **Muted** | `#444444` dark grey | Timed-out troublemakers | Deny Send Messages, Add Reactions, Speak everywhere |

**@everyone:** View Channels, Read Message History, Send Messages (in the community channels only), Connect and
Speak in voice. Turn off Mention @everyone, Create Invite (optional), and Attach Files (Builders get it).

---

## 2. Categories and channels

### 📌 INFORMATION (read-only for @everyone)
| Channel | Topic |
|---|---|
| `#welcome` | Welcome to \|CelMod\| — A Living Project. Start here. |
| `#rules` | Server rules. Breaking them in game or here gets the same treatment. |
| `#announcements` | Updates, events and news. Grab the @Updates role to get pinged. |
| `#server-info` | How to join, the website, and useful commands. |
| `#roles` | React to get @Events and @Updates pings. |

### 💬 COMMUNITY
| Channel | Topic |
|---|---|
| `#general` | Talk about anything CelMod. |
| `#builds` | Show off your builds. Screenshots and videos only, chat in threads. |
| `#trading` | Trade emblems, celweps, shop props and CL. Trades happen in game with !trade or !give. |
| `#events` | Mazes, parkour, build contests and emblem drops. |
| `#off-topic` | Everything else. |

### 🛠️ CELMOD
| Channel | Topic |
|---|---|
| `#help` | Stuck? Ask here. The guides: https://celmod.net/guides.php |
| `#suggestions` | Ideas for the server. One per message; vote with 👍 / 👎. Use a forum channel if your server has them. |
| `#bug-reports` | Found a bug? Say what happened, on which map, and what you were doing. In game: !reportbug. |

### 🔒 STAFF (only Owner, Admin, Moderator can see)
| Channel | Topic |
|---|---|
| `#staff-chat` | Staff talk. |
| `#disputes` | Player disputes (in game: !dispute). Note the SourceTV demo time if there is one. |
| `#mod-log` | Bans, kicks and timeouts, with the reason. |

### 🔊 VOICE
| Channel | Notes |
|---|---|
| `Lounge` | Hang out. |
| `Building Together` | For people building in the same land. |
| `Event Stage` | Stage channel for events; Event Hosts are speakers. |
| `AFK` | Set as the server's AFK channel (5 minutes). |

---

## 3. Ready-to-post messages

### `#welcome`

> **Welcome to |CelMod| — A Living Project!** 🏗️
>
> CelMod is a Half-Life 2: Deathmatch build server: claim a land, spawn hundreds of props, build anything,
> collect rare emblems and hats, dig for treasure, trade with other players and take part in events.
>
> **Get started**
> 1. Read #rules.
> 2. Check #server-info for how to join.
> 3. New to building? The guides are at https://celmod.net/guides.php
> 4. Grab your ping roles in #roles.
>
> Have fun building!

### `#rules`

> **|CelMod| Rules** — the same rules apply in game and on Discord.
>
> **1. Be friendly.** No harassment, hate or spam.
> **2. Respect builds.** Don't wreck, steal from or block other players' builds. In game, use !landban if someone bothers you.
> **3. No exploits.** No crash props, lag machines or abusing bugs. Report bugs in #bug-reports instead.
> **4. Events are fair.** Event areas (mazes and parkour) are walked, not flown. No building inside them.
> **5. Trades are final.** Trade in game with !trade or !give. Staff can't undo a trade you agreed to.
> **6. Keep channels on topic.** Builds in #builds, trades in #trading, and so on.
> **7. Listen to the staff.** If you disagree with a decision, message an Admin privately.

### `#server-info`

> **How to join**
> Open Half-Life 2: Deathmatch, then the console, and type: `connect <your server address>`
> Or use the "Connect to the server" link at the bottom of https://celmod.net
>
> **Useful links**
> • Website: https://celmod.net
> • Commands: https://celmod.net/cmds.php
> • Props list: https://celmod.net/props/
> • Guides: https://celmod.net/guides.php
> • Shop: https://celmod.net/shop.php
> • Live server: https://celmod.net/live.php
>
> **First commands in game**
> `!land` claim a land • `!spawn <prop>` spawn a prop • `!save <name>` save your build • `!bank` your items • `!cmds` every command

### `#roles`

> React to get pinged:
> 🎉 — **@Events** (mazes, parkour, build contests, emblem drops)
> 📰 — **@Updates** (new server updates)

Use Discord's built-in **Onboarding / Channels & Roles** (Server Settings → Onboarding) to hand these out, or a
reaction-role bot.

---

## 4. Server settings

- **Verification level:** Medium (registered on Discord for 5 minutes).
- **Explicit content filter:** Scan messages from all members.
- **Default notifications:** Only @mentions.
- **AutoMod:** turn on "Block commonly flagged words" and "Block mention spam" (5+ mentions).
- **Community:** enable it, then set #rules as the Rules channel and #announcements as the Community Updates channel.
- **System messages:** send join messages to #general.

---

## 5. Optional: post updates automatically

The website already lists every update. To post new ones into #announcements:

1. In #announcements: **Edit Channel → Integrations → Webhooks → New Webhook**, and copy its URL.
2. Keep that URL secret, like a password. Anyone with it can post in the channel.
3. Ask for the website's admin updates page to send each new update to that webhook. (Not built yet.)
