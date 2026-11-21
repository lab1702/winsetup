# Fixing httpgd in VS Code's R extension 2.x with R 4.6 or later on Windows

> **This guide is for vscode-R 2.x only.** vscode-R 3.0.0 (September 2026)
> rewrote the session watcher around its `sess` package and works with R 4.6,
> so updating the extension is the simplest fix. 3.x no longer uses
> `%USERPROFILE%\.vscode-R\init.R` or the `vsc.*` R options, and
> `r.plot.useHttpgd` became `r.plot.backend`, so the root cause and the
> workaround below don't apply to it. If you used this workaround and then upgraded to
> 3.x, remove the block from your `.Rprofile` and delete the leftover
> `%USERPROFILE%\.vscode-R` folder.

If you've enabled httpgd for graphics in the VS Code R extension
(`reditorsupport.r`) 2.x but plots still open in a **separate `windows()` device**
instead of the httpgd viewer tab, and you use **R 4.6 or later**, this guide is
for you.

## Symptoms

- `r.plot.useHttpgd` is `true` in your settings, and the `httpgd` package is
  installed, yet plots open in a standalone OS window.
- In your R session, `getOption("vsc.use_httpgd")` returns `NULL`.
- `"tools:vscode" %in% search()` returns `FALSE` (the extension's session
  features never attached).

## Root cause

vscode-R 2.x defers its real work (sourcing its session script, attaching the
`tools:vscode` environment, and registering the httpgd graphics device) until R
has loaded its default packages. To do that, its init script, which runs while R
reads its startup profile, installs a hook as a **global-environment
`.First.sys`** function, counting on R's startup to call it instead of base R's
own `.First.sys`.

R 4.5 and earlier evaluated that `.First.sys()` call in the global environment,
so the hook took precedence and ran. **Starting with R 4.6.0, R calls the base
package's `.First.sys` instead**, so the hook is installed but never called, and
the session features never load. This happens however the init script is
loaded, and wherever your home or Documents folder is (see vscode-R issue
[#1696](https://github.com/REditorSupport/vscode-R/issues/1696)).

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
3. Sources the extension's watcher init from `%USERPROFILE%\.vscode-R\init.R`,
   where vscode-R 2.x writes it (this works even if R's `~` points elsewhere,
   such as a OneDrive-redirected Documents folder).
4. **Explicitly invokes** the deferred `.First.sys` hook, since R 4.6 and later
   won't call it.

```r
# vscode-R 2.x session watcher loader (workaround for R 4.6 and later).
#
# Background:
#  * vscode-R 2.x's init defers its real work (sourcing its session script,
#    attaching tools:vscode, registering the httpgd device) by installing
#    init_last as a global-env .First.sys hook. Since R 4.6.0, R's startup calls
#    base R's .First.sys instead, so the hook is installed but never fires. We
#    therefore source the init here and call the hook ourselves.
#  * The init is read from %USERPROFILE%\.vscode-R, where vscode-R writes it,
#    even if R's "~" points elsewhere (e.g. a OneDrive-redirected Documents).
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
      # tryCatch: an error here would stop the rest of R's startup profile, e.g.
      # when init.R was left behind by vscode-R 2.x after an upgrade to 3.x.
      tryCatch({
        source(vscr_init)  # installs init_last as a global-env .First.sys hook
        # R 4.6 and later don't call the global-env .First.sys override, so run
        # it now to complete vscode-R initialization.
        # inherits = FALSE: don't pick up base::.First.sys if vscode-R installed no hook
        if (exists(".First.sys", envir = globalenv(), inherits = FALSE)) {
          hook <- get(".First.sys", envir = globalenv(), inherits = FALSE)
          hook()
        }
      }, error = function(e)
        message("[.Rprofile] vscode-R init failed: ", conditionMessage(e)))
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
  keep even on machines without the extension. After upgrading to vscode-R 3.x,
  remove it as described at the top of this guide. Note that if your `.Rprofile`
  lives under OneDrive it will sync to your other machines.

## Verify

In an extension-launched R terminal:

```r
"tools:vscode" %in% search()   # TRUE
getOption("vsc.use_httpgd")    # TRUE
plot(1:10)                     # should appear in the httpgd viewer tab
```

If all three look right, you're done.

## Permanent fix

Update the extension to vscode-R 3.0.0 or later, which no longer depends on
`.First.sys`. Then remove the `.Rprofile` block and the leftover
`%USERPROFILE%\.vscode-R` folder, and set `r.plot.backend` instead of
`r.plot.useHttpgd`.
