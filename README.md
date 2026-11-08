# Calculator18

Brings the iOS 18 Calculator to iOS 15–17:

- Full expression shown above the result.
- iOS 18-style calculator key (bottom-left) with a menu to switch between basic and scientific keypads, or open a New Note. Combine it with Notemath18 to open Apple Note and perform complex calculations.
- Clear key works like iOS 18: it deletes one character at a time, and holding it clears everything.
- Fully support for landscape mode.

Supports iOS 15.0 – 17.x, rootless and roothide.

## Build

<details>
<summary>Build instructions</summary>

Build the package with roothide's fork of Theos. 

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide

```
Add `CALCULATOR18_DEBUG=1` for a debug build that logs the keypad layout.

</details>


## License

Calculator18 is licensed under the GNU General Public License, version 3 only. See [LICENSE](LICENSE).
