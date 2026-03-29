# _simmerblau_&mdash;parameterized color palettes for VMD

_Simmerblau_ lets you generate pleasing color ramps in [VMD][vmd]. It is inspired by and based on
the fantastic [RampenSau][rampensau]. To learn about the technical details behind the color
generation, please look at that project. _Simmerblau_ is simply a Tcl port of that color generation
logic with a user interface for VMD.

## Installation

To install _simmerblau_, download the repository and execute the `vmd_install.tcl` script.

```sh
# Download simmerblau to a location of your choice. For example, by cloning the repository.
git clone https://github.com/ma3ke/simmerblau
cd simmerblau
# Run the installation script.
vmd -e vmd_install.tcl
```

The installer registers the plugin at the bottom of your `.vmdrc` or `vmd.rc` on Windows (do people
actually do that???) and will load it immediately into the current session. After installation, you
can run VMD anywhere and find _simmerblau_ under **Extensions > Visualization > Simmerblau Colors**.

## Usage

With _simmerblau_, you can set both the Color scale and Color IDs 0–32 (excluding white, which is
typically used as a sensible background color).

By ticking the _Live preview_ box, all changes to the palette are immediately applied to VMD's
state.

Individual Color ID values can be locked by clicking on a color in the discrete palette preview
(left side of the vertical color bar). This will _lock_ that specific slot, pinning certain colors
while randomizing or adjusting the rest of the parameters.

## Credits

_Simmerblau_ was developed by Marieke Westendorp & Aster Kovács, 2026.
The color generation is based on [RampenSau][rampensau] by David Aerne (@meodai) et al.

[vmd]: https://www.ks.uiuc.edu/Research/vmd
[rampensau]: https://github.com/meodai/rampensau
