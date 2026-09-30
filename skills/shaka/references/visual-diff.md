# Make a difference image

Use an image tool that is already available. `command -v magick` shows whether
ImageMagick 7, an [optional prerequisite](installation.md#prerequisites), is installed. A project's own screenshot tests may also produce
difference images; Playwright's `toHaveScreenshot`, for example, writes one when
an assertion fails.

When no tool is available, skip the difference image. Say so beside the captures,
for example “No difference image: no image comparison tool on this machine,” and
publish the clearest labeled before and after pair. Installing software on the
machine or adding a project dependency just for this evidence needs the user's
approval.

With ImageMagick 7, confirm the two captures have the same size, then write the
difference:

```sh
magick identify -format '%f %wx%h\n' before-desktop.png after-desktop.png
magick compare -metric AE before-desktop.png after-desktop.png diff-desktop.png
```

Compare the printed sizes yourself. `compare` still produces a result for images
of different sizes, and that result misleads the reviewer.

`compare` fades unchanged pixels and paints changed ones red. It prints the changed
pixel count and exits with status 1 when the images differ, so allow that exit in
scripts.

Keep this exact comparison as the evidence, because a subtle color or opacity
change is often the point of the PR. When antialiasing or font rendering covers
the image in red, add a second image made with `-fuzz 2%`, which treats nearly
identical colors as equal, and label it as filtered. A filtered image can show no
change where the exact one does.

Attach the difference beside its source captures in one PR comment, as with any
capture. Put the label in the comment text or alt text; ImageMagick's `montage`
labels need a configured font and fail on some machines.
