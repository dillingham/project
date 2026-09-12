# Catalogue pages

Some pages are a catalogue rather than a narrative: every field type, every available method. They take a different shape, and it is rigid.

The page carries an index first and the entries after it. The index is a flat list of links under its own `##`, grouped by family if it is long. The entries follow under a second `##`, in the same order.

Each entry is invariant:

```markdown
#### `padLeft()`

The `padLeft` method pads the left side of a string until it reaches a given length:

    ```php
    $padded = padLeft('James', 10, '-=');

    // '-=-=-James'
    ```
```

The parts that do not vary:

- The heading is the name with parentheses, in backticks. Nothing else.
- The first sentence opens `The \`name\` method ...`, describes what it does in present tense, and ends in a colon. Never "This method will..." and never a heading followed straight by code.
- The example includes whatever import or setup line the reader would need to paste it.
- The result is a trailing comment, never a sentence.
- An extra parameter earns one more colon-terminated sentence and one more small block.
- The entry ends on its last code block. No summary, no closing thought.

Reference entries are `####` headings, so they stay out of the table of contents. The index is the navigation.
