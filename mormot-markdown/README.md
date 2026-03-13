# mormot.ext.markdown

Markdown-to-HTML processor for [mORMot v2.*](https://github.com/synopse/mORMot2).

## Features

- **Four dialects**: Daring Fireball, TxtMark, CommonMark, GitHub (GFM)
- **Single unit** (`mormot.ext.markdown.pas`) - no extra dependencies beyond mORMot v2 core
- **Safe mode** - filters `<script>`, `<applet>`, and other unsafe HTML elements
- Tables (with `<thead>`/`<tbody>`, column alignment), fenced code blocks, smart typography, strikethrough, heading IDs, task lists, bare URL autolinks

## Quick Start

### One-liner

```pascal
uses
  mormot.ext.markdown;

var
  html: RawUtf8;
begin
  html := MarkdownToHtml('# Hello World');
end;
```

### With options

```pascal
var
  md: TMarkdownProcessor;
begin
  md := TMarkdownProcessor.Create(mdGitHub);
  try
    md.SafeMode := True;
    html := md.Process('Some **markdown** text');
  finally
    md.Free;
  end;
end;
```

### Dialects

| Dialect | Description |
|---------|-------------|
| `mdDaringFireball` | The original - bare minimum |
| `mdTxtMark` | + smart typography, fenced code, heading IDs |
| `mdCommonMark` | + tables, strikethrough, sub/sup, ins, mark, math |
| `mdGitHub` | GFM - like CommonMark + task lists, bare URL autolinks, without sub/sup/ins/mark/math |

```pascal
md := TMarkdownProcessor.Create(mdGitHub);    // GFM, most common
md := TMarkdownProcessor.Create(mdCommonMark); // default
```

`mdGitHub` follows the [GFM spec](https://github.github.com/gfm/): tables, strikethrough (`~~text~~`), task lists (`- [x] done`), and bare URL autolinks (`https://...`, `www....`). CommonMark-only extensions (`++ins++`, `==mark==`, `~sub~`, `$math$`) are not active in GFM.

### Custom HTML output

Subclass `TMarkdownDecorator` to customize the generated HTML tags:

```pascal
type
  TMyDecorator = class(TMarkdownDecorator)
  public
    procedure OpenParagraph(W: TTextWriter); override;
  end;

procedure TMyDecorator.OpenParagraph(W: TTextWriter);
begin
  W.AddShort('<p class="custom">');
end;

md := TMarkdownProcessor.Create(mdGitHub, TMyDecorator.Create);
```

## Demo

See `demos/vcl-markdown/` for a VCL app with live preview.

## Tests

Tests cover all dialects, GFM extensions, and edge cases:
