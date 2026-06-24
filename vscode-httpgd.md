# Fixing httpgd in VS Code's R extension on Windows with OneDrive

If you've enabled httpgd for graphics in the VS Code R extension
(`reditorsupport.r`) but plots still open in a **separate `windows()` device**
instead of the httpgd viewer tab, and your **Documents folder is managed by
OneDrive**, this guide is for you.

## Symptoms

- `r.plot.useHttpgd` is `true` in your settings, and the `httpgd` package is
  installed, yet plots open in a standalone OS window.
- In your R session, `getOption("vsc.use_httpgd")` returns `NULL`.
- `"tools:vscode" %in% search()` returns `FALSE` (the extension's session
  features never attached).

## Root cause

There are two layers:

1. **OneDrive "Known Folder Move" redirects your Documents folder.** As a result,
   R resolves `~` (its home directory) to something like
   `C:\Users\<you>\OneDrive\Documents`, while the VS Code R extension writes its
   session-watcher files to your real user profile,
   `%USERPROFILE%\.vscode-R` (i.e. `C:\Users\<you>\.vscode-R`). The extension's
   automatic session initialization can't find its own files, so it never runs.

2. **The documented manual fallback doesn't fully fire.** vscode-R's init defers
   its real work (sourcing its session script, attaching the `tools:vscode`
   environment, and registering the httpgd graphics device) by installing a hook
   as a **global-environment `.First.sys`** function. R only invokes that
   global-env override when the init is loaded via the extension's own
   `R_PROFILE_USER` mechanism — **not** when you load it from your `~/.Rprofile`.
   So even after sourcing the init manually, the hook sits there, never called.

## The fix

Create (or edit) an `.Rprofile` in **R's home directory** with the contents
below. To find R's home directory, run this in an R console:

```r
normalizePath("~")
```

That's where the file must go (e.g. `<R-home>/.Rprofile`).

The script does four things:

1. Adds your user package library to `.libPaths()` so `httpgd` is discoverable
   during early startup.
2. Pre-sets `vsc.use_httpgd = TRUE` (vscode-R won't override an option you've
   already set, so this guarantees the httpgd device is chosen).
3. Sources the extension's watcher init from `%USERPROFILE%\.vscode-R\init.R`
   (the correct location, regardless of where `~` points).
4. **Explicitly invokes** the deferred `.First.sys` hook, since R won't fire it
   for us.

```r
# vscode-R session watcher loader (OneDrive "Known Folder Move" workaround).
#
# Background:
#  * OneDrive redirects Documents, so R's "~" is OneDrive\Documents while vscode-R
#    writes its watcher files to %USERPROFILE%\.vscode-R -- so the extension's
#    automatic init never loads. We load it explicitly here.
#  * vscode-R's init defers its real work (sourcing its session script, attaching
#    tools:vscode, registering the httpgd device) by installing init_last as a
#    global-env .First.sys hook. When loaded from ~/.Rprofile (rather than the
#    extension's R_PROFILE_USER), R does NOT invoke that override, so the hook is
#    installed but never fires. We therefore call it ourselves after sourcing.
#  * We pre-set vsc.use_httpgd = TRUE; vsc.R won't override an option the user
#    already set, guaranteeing the httpgd device is selected.
if (interactive() && Sys.getenv("TERM_PROGRAM") == "vscode") {
  local({
    up <- Sys.getenv("USERPROFILE")
    vscr_init <- file.path(up, ".vscode-R", "init.R")
    if (nzchar(up) && file.exists(vscr_init)) {
      # Make sure the user package library is visible so httpgd is found.
      ver <- paste(R.version$major, sub("\\..*$", "", R.version$minor), sep = ".")
      ulib <- file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-library", ver)
      if (dir.exists(ulib) && !(ulib %in% .libPaths())) {
        .libPaths(c(ulib, .libPaths()))
      }
      options(vsc.use_httpgd = TRUE)
      source(vscr_init)  # installs init_last as a global-env .First.sys hook
      # The global-env .First.sys override does not auto-fire when loaded from
      # ~/.Rprofile, so run it now to complete vscode-R initialization.
      if (exists(".First.sys", envir = globalenv())) {
        hook <- get(".First.sys", envir = globalenv())
        tryCatch(hook(), error = function(e)
          message("[.Rprofile] vscode-R init failed: ", conditionMessage(e)))
      }
    }
  })
}
```

## Prerequisites and notes

- Make sure the `httpgd` package is installed: `install.packages("httpgd")`.
- Make sure `r.plot.useHttpgd` is `true` in your VS Code settings.
- **Start R via the extension** — use the Command Palette's
  *R: Create R Terminal*, or simply send code with `Ctrl+Enter` /
  `Ctrl+Shift+S`. Do **not** use the editor's Run button or type `R` into a plain
  terminal; those launch an R process the extension doesn't manage, so the
  session features won't load.
- The `.Rprofile` is guarded (`interactive()`, `TERM_PROGRAM == "vscode"`, and a
  `file.exists()` check), so it's a no-op outside a vscode-R session and safe to
  keep even on machines without the extension. Note that if your `.Rprofile`
  lives under OneDrive it will sync to your other machines.

## Verify

In an extension-launched R terminal:

```r
"tools:vscode" %in% search()   # TRUE
getOption("vsc.use_httpgd")    # TRUE
plot(1:10)                     # should appear in the httpgd viewer tab
```

If all three look right, you're done.

## Cleaner permanent alternative

Instead of the `.Rprofile` workaround, you can fix the underlying mismatch by
making R's home agree with the extension. Set a **Windows user environment
variable** `R_USER` to `%USERPROFILE%`:

1. Start menu → "Edit environment variables for your account".
2. Add a new user variable: name `R_USER`, value `%USERPROFILE%`
   (or the literal expanded path, e.g. `C:\Users\<you>`).
3. Restart VS Code.

With this set, R's `~` matches `%USERPROFILE%`, the extension's automatic init
works on its own, and the `.Rprofile` above is no longer needed.
