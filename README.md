I was thinking, how hard would it be to make a browser, with alternative framework.

So here it is: Lua + OpenGL + SDL + ImGUI.

Capable of loading `file://` and `http://`.

### Discussion

Should `require` in pages consider paths relative to the page. i.e. possibly remote paths, before they consider local require paths / browser require paths?

Yes: for modular design and seamless integration of pre-existing Lua code?

No: this would put the slowest `require()` loader first.

Alternatively I could use a separate function for remote-require... but this would break standalone app compatability.
