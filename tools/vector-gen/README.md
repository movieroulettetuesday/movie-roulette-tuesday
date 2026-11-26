# Catalog vector generator

Regenerates the shared oracle vectors (`test-vectors/*.json` and `data/*.json`) by compiling this repo's `MovieRouletteTuesday/RouletteCore` sources unchanged and running them. Do not edit the generated JSON by hand.

## Run

On a Mac with Xcode, and not during an archive or a UI test lane:

```
tools/vector-gen/gen-mac.sh <ios-checkout> <out/test-vectors>
```

`<ios-checkout>` is a checkout of this repo whose `RouletteCore` and `MovieRouletteTuesday/Resources/movies.json` should be used. `<out/test-vectors>` is the directory for the seven vector JSON files. The three `data/` files are written beside that directory, in `../data`. A `build.log` is written beside the output directory.

## Arguments and environment

The tool does not use API tokens, keys, or passwords. Paths and the commit id are not hard-coded; they come from arguments, plus one optional environment variable:

- `gen-mac.sh` argument 1: path to the iOS checkout. Passed through to the generator as its second argument.
- `gen-mac.sh` argument 2: output directory for the vector JSON files. Passed through as the generator's first argument.
- iOS commit: `git -C <ios-checkout> rev-parse --short HEAD`, passed as the generator's third argument and recorded in the generated files.
- `MRT_ANDROID_FEED_SAMPLE`: optional. If set to a file path, that RSS sample is included in `rss.json`.

Do not add tokens, keys, passwords, or personal machine paths to these files.
