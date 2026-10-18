# Repository Guidelines

## Language

All text output uses ASD-STE100 Simplified Technical English.

## Documentation

Documentation is in the `doc/` directory. Documentation is descriptive and
declarative. Documentation never uses the imperative mood. Documentation never
refers to a file in the `plan/` directory.  Documentation is in markdown with
proper front matter no more than 20 lines long.

## Plans

Plans are in the `plan/` directory. A plan can refer to a document in the
`doc/` directory.

i plans are always git ignored

## Pascal File Header

Each Pascal file starts with a pasdoc documentation comment. The comment
wraps YAML front matter. The front matter holds a `license` key and a
`copyright` key. and any other useful keys, no more than 20 lines.

```pascal
{**
---
license: ${MyLicense}
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: important_thing
notes:
  - this is a note
  - this is a note
---
}
unit Example;
```

- The comment is a pasdoc comment. The opening `{**` is on its own line. The
  `license` key follows on the next line.
- The `license` value is the SPDX license identifier. In the examples it is
  written `${MyLicense}`. The `License` section of the README holds the
  identifier and the full license name. A Pascal file uses the identifier
  from that section.
- The `copyright` value holds the copyright holder and the year.
- Additional keys are permitted.
- A line with three hyphens (a `---` line) closes the front matter.
- The closing `}` is on its own line.

```pascal
{**
---
license: ${MyLicense}
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: scanner
documentation: doc/architecture.md 
notes:
  - this implements the string scanner
---

}
unit YamlPuller.Scanner;
```

## Pascal Source

- A Pascal file is less than 2000 lines long. A Pascal file expresses one
  concept or type, or one related set of concepts.
- A Pascal method is less than 500 lines long. This limit is a soft limit. A
  Pascal method expresses one responsibility, don't create trivial methods just to hit the limit,
  long 'case' or dispatch methods are fine.

## Build System
- both makefile and lazarus build files are maintained in parity
