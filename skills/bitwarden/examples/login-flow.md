# Browser login flow: worked example

The full command sequence for logging into a site with a Bitwarden vault item. All output is **illustrative**; the values are sanitized placeholders. Commands use the handle `laptop`, the folder `Agent`, and the Linux paste chord `ctrl+v` (`cmd+v` on macOS).

## Step 0: Select a browser on this machine

`bw-fill` fills this machine's clipboard, so the paste must target a browser on the same machine. Pasting into a browser elsewhere silently does nothing.

## Step 1: Resolve the folder ID

```bash
bwx laptop list folders | jq -r '.[] | select(.name == "Agent") | .id'
```

```
a1b2c3d4-0000-0000-0000-000000000001
```

Store it as `<F>`. It is stable, so resolve it once per machine.

## Step 2: Find the item, password filtered out

```bash
bwx laptop list items --folderid a1b2c3d4-0000-0000-0000-000000000001 --search example.com \
  | jq '.[] | {id, name, username: .login.username}'
```

```json
{
  "id": "xxxxxxxx-0000-0000-0000-000000000042",
  "name": "Example Site",
  "username": "user@example.com"
}
```

Without the `jq` filter, `bw list items` prints every field of each item, **including the password**.

## Step 3: Type the username

Type `user@example.com` into the username field.

## Step 4: Copy the password

Focus the password field, then:

```bash
bw-fill laptop xxxxxxxx-0000-0000-0000-000000000042
```

Output: `copied`. The password goes from `bw` straight into the clipboard tool; nothing is written to stdout.

## Step 5: Paste and clear

Send `ctrl+v`, then clear the clipboard at once, whether or not the paste worked:

```bash
bw-fill --clear
```

Output: `cleared`. Never check the paste by reading the clipboard back.

Submit the form.

## Notes

- Two-factor codes are out of scope; the user enters them.
- If a wrapper reports an expired or missing session, `bwx` and `bw-fill` re-unlock on every call; check the three `bw-*-<handle>` secret-store entries.
- If the field stays empty after the paste, the wrong browser is almost always selected: clear the clipboard, redo Step 0, retry once, then hand the login to the user.
