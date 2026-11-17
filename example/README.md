# flutter_matter_google_home example

This example demonstrates the plugin without depending on any external Matter
commissioner.

- **Commission only** runs a Google-only flow.
- **Start handoff session** waits for Google provisioning and exposes a handoff.
- The example then asks the operator to report the external second-fabric
  success or failure. It intentionally does not implement a second fabric.

Set `GOOGLE_MATTER_SDK_REPO` before building:

```bash
export GOOGLE_MATTER_SDK_REPO=/absolute/path/to/unzipped/repo
fvm flutter build apk --debug
```

The onboarding payload field is obscured and is not logged or persisted.
