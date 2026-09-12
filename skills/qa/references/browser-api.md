# The browser API, and the traps in it

Reference for `pestphp/pest-plugin-browser`, for repos whose browser proofs are Pest. Read the [skill](../SKILL.md) for when to reach for any of this - this file is only what is available.

## Visiting

`visit($url)` returns a page you chain everything onto. It takes an array of URLs too, which drives them together and then destructures - the cheapest broad sweep available, and worth running across a feature's routes before hunting anything specific.

```php
$pages = visit(['/users', '/users/new', '/orders', '/orders/new']);

$pages->assertNoSmoke();   // console logs and JS errors are both inside this one

[$index, $create] = $pages;
$create->assertSee('Create user');
```

`->navigate('/elsewhere')` moves one page on without a fresh visit.

The viewer's context chains before the assertions, and this is where the skill's sixth seam lives - a page under a real timezone, locale, colour scheme or device is a different page.

```php
visit('/orders')->inDarkMode();
visit('/orders')->withTimezone('Australia/Sydney');
visit('/orders')->withLocale('de-DE');
visit('/orders')->on()->iPhone15Pro();      // ->on() carries a device roster
visit('/orders')->from()->tokyo();          // ->from() carries geolocation
```

## Selectors

`assertCount`, `assertPresent`, `click` and friends all run their argument through `GuessLocator`. Reach for these in order:

1. **`'@thing'`** - the test-id form, resolving to `[data-testid=thing], [data-test=thing]`. This is the preferred selector: it decouples the test from styling and structure.
2. **A stable semantic selector** - `form[action="/members"]`, `[name=email]`, `[id="..."]`. What something IS or where it posts, not how it is painted.
3. **`assertScript`** - only for a relationship or an invariant no selector can name.

Never select positionally (`querySelectorAll("form")[1]`) unless the position IS the claim. A Tailwind class is not a selector; it changes when someone restyles.

**A bare word is not treated as CSS.** `'form'` is looked up as `[id="form"]`, then `[name="form"]`, then as page text - it will not match the form elements. A selector counts as explicit only if it starts with `#`, `.`, `[` or `internal:`, or contains one of `[ ] # > + ~ : * | ^ , = ( )`. So write `'form[action]'`, not `'form'`. An explicit selector goes to Playwright's `locator()` verbatim, in strict mode, so it must resolve to exactly one element for the single-element assertions.

## Asserting

Prefer a named assertion when one says the claim exactly - it produces a readable failure and does not need reading twice.

```php
->assertCount('@form', 2)
->assertPresent('form[action="/members"]')
```

Reach for `assertScript()` only when the claim is about a **relationship between elements** - a page-wide invariant, or where focus went - which is what most assembly bugs are and what no named assertion expresses. There is no focus assertion in the plugin, so focus is always script.

The first argument is a JS expression or an immediately-invoked function; the second is the expected value, defaulting to `true`.

**Return the offending value, not a boolean.** Expecting `[]` fails with `0 => 'name'` and names the colliding field; expecting `true` fails with `false` and sends the reader back to the page. The diff is the whole diagnostic, so make it carry the answer.

```php
// good - the failure says WHICH id collided
->assertScript('(() => {
    const ids = [...document.querySelectorAll("[id]")].map((e) => e.id);
    return ids.filter((id, i) => ids.indexOf(id) !== i);
})()', [])
```

| Family | Assertions |
| --- | --- |
| Presence | `assertVisible` `assertPresent` `assertNotPresent` `assertMissing` `assertCount` |
| Text | `assertSee` `assertDontSee` `assertSeeIn` `assertSeeNothingIn` `assertSeeLink` `waitForText` |
| Form state | `assertValue` `assertChecked` `assertNotChecked` `assertSelected` `assertRadioSelected` `assertEnabled` `assertDisabled` `assertIndeterminate` |
| Attributes | `assertAttribute` `assertAttributeContains` `assertAttributeMissing` `assertAriaAttribute` `assertDataAttribute` |
| Source | `assertSourceHas` `assertSourceInHas` `assertSourceMissing` |
| URL | `assertPathIs` `assertRoute` `assertQueryStringHas` `assertQueryStringMissing` `assertUrlIs` `assertFragmentIs` |
| Console | `assertNoJavaScriptErrors` `assertNoConsoleLogs` `assertNoSmoke` `assertNoBrokenImages` `assertNoAccessibilityIssues` |
| Visual | `assertScreenshotMatches` |

## Interacting

```php
->click('Create order')     ->press('Create order')     ->pressAndWaitFor('Save', 2)
->fill('email', 'a@b.c')    ->type('email', 'a@b.c')    ->typeSlowly('email', 'a@b.c')
->select('country', 'GB')   ->check('notify')           ->uncheck('notify')
->radio('plan', 'pro')      ->clear('notes')            ->append('notes', ' more')
->keys('@form', ['Tab'])    ->hover('@table-row')       ->drag('@a', '@b')
->attach('avatar', $path)   ->withKeyDown('Shift', fn () => ...)
->refresh()  ->back()  ->forward()  ->navigate('/elsewhere')
```

## Exploring

For when a scenario cannot be built in the dev app and you need to look at it.

```
vendor/bin/pest tests/<proofs>/TwoFormsTest.php --headed
```

```php
->wait(2)          ->waitForKey()      // hold the page open
->screenshot()     ->debug()           // capture it
->dd()             ->tinker()          // stop inside it
```

`--headed` is refused under `--parallel`, so a browser suite anyone wants to watch cannot run parallel. Failure screenshots land in `tests/Browser/Screenshots` - a path the plugin hardcodes regardless of where the tests live, so that directory exists only to hold them. Gitignore it.

## Waiting

Assertions wait for the element on their own, 5 seconds by default. Raise it globally in `tests/Pest.php` rather than sprinkling sleeps:

```php
pest()->browser()->timeout(10_000);
```

`->wait(2)` and `->pressAndWaitFor('Save', 2)` exist, and a fixed sleep is the usual way a browser suite becomes slow and flaky at once. Prefer `waitForText()` or an assertion that already waits.

## Where proofs can live

The plugin boots the Laravel kernel **in-process** (`Pest\Browser\Drivers\LaravelHttpServer`), so routes registered in `beforeEach` and rows made by factories are both visible to the page - the browser hits the same kernel and the same database as the test. A proof needs no route file of its own.

A test becomes a browser test by calling `visit(` in its own closure, so a file can mix plain request assertions with browser ones and only the browser half pays for a browser. Two traps in that. Detection reads the closure's own source, so a `visit()` hidden behind a helper is invisible to it and the test runs without a browser set up - **call `visit()` directly in the test.** And under `tests/Browser` the rule does not apply: `Pest\Browser\Support\BrowserTestIdentifier` marks every file there whether it visits or not, so keep mixed proofs in a directory with another name.

## Traps

**Synthetic events lie, in both harnesses.** React's `onBlur` is the native `focusout`, so `el.dispatchEvent(new FocusEvent('blur'))` fires nothing and a handler looks broken when it is fine. Setting `.value` directly is equally invisible to React - go through the property descriptor's setter and dispatch `input` and `change`, or better, use a real interaction. A negative result from a synthetic event is worth nothing until a real one confirms it.

**`assertNoAccessibilityIssues()` is a smoke check, not a hunt** - see the [skill](../SKILL.md) for what it missed and why that matters.

**The accessibility snapshot is not the DOM.** When exploring with the chrome-devtools MCP tools, a `take_snapshot` combobox shows its selected option's *label*, and it can disagree with what the element's `value` actually is. Confirm anything surprising with `evaluate_script` before believing it.

**A stale MCP Chrome blocks the profile.** `The browser is already running for .../chrome-profile` means a previous session's Chrome is still holding it. Kill just those processes: `pkill -f "user-data-dir=$HOME/.cache/chrome-devtools-mcp/chrome-profile"`.
