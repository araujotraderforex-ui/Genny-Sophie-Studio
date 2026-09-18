# Gênny & Sophie Studio

Android ARM64 prototype for the Galaxy A55 5G. The [Studio APK workflow](.github/workflows/a55-local-diffusion.yml) builds a single app with the Studio interface and the native [Local Diffusion](https://github.com/rmatif/Local-Diffusion) engine, pinned to commit `184b7f92cf2f810e7d5eb4b04b190a5da829005f`. Local Diffusion is licensed under Apache 2.0.

## What the app does

- Text commands and Android voice recognition in Portuguese.
- Gênny or Sophie selector.
- Text to image, or image to image using an optional gallery reference.
- 512 × 512 image generation on CPU; generated PNGs remain in the app's private documents folder.
- First launch downloads the public [Stable Diffusion 1.5 checkpoint](https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/blob/main/v1-5-pruned-emaonly.safetensors), resumes interrupted downloads, checks SHA-256, and then loads it locally. The model is governed by its [CreativeML Open RAIL-M license](https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/blob/main/LICENSE).
- First setup needs approximately 5 GB free storage and a download of approximately 4.3 GB. After setup, image generation uses no hosted inference service.

## Current limits

The base SD 1.5 checkpoint does **not** contain trained Gênny or Sophie identities. Selecting a name adds it to the prompt; the reference image uses img2img and does not guarantee facial identity. The APK can be checked for compilation in GitHub Actions, but inference, speed, and memory use require a test on an actual Galaxy A55. Voice recognition depends on an installed Android recognition provider and may use that provider's network service. Generated files currently live in app private storage.

The native Kotlin project in `app/` is a historical prototype and is not the APK delivered by the Studio workflow. Only the artifact named `Genny-Sophie-Studio-A55` is the integrated build.

## Build

Open the latest successful run of the Studio workflow under GitHub Actions and download its `Genny-Sophie-Studio-A55` artifact. The APK inside is a release build signed with a debug key for testing. The repository's `flutter_overlay/` contains the Studio source; CI applies it to the pinned upstream engine and builds Android ARM64.
