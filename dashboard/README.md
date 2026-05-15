# Dashboard Dev Notes

Run the dashboard locally with:

```bash
npm run dev
```

For an exact small-screen composition harness, open:

```text
http://localhost:5173/?preview=compact-480x320&tab=settings
```

That preview renders the app inside a fixed `480x320` frame and forces the compact layout so spacing work can be done against the real screen bounds before pushing to the Pi.

The live kiosk uses the same compact path when opened with:

```text
http://localhost/?profile=generic-ili9486-hat
```
