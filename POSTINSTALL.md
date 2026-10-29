OpenCode can run arbitrary commands inside this app. Only give access to people you trust.

<sso>
Sign in with your Cloudron account and OpenCode opens straight away.
</sso>

<nosso>
OpenCode is protected by its own server password. To read it, open the app's Web Terminal and run:

```
opencode service get password
```

Then choose **Use password** on the OpenCode connect screen.
</nosso>

Next, connect a model provider under **Settings → Providers**, or add API keys to `/app/data/env.sh`
and restart the app. Put projects in `/app/data/workspace`.
