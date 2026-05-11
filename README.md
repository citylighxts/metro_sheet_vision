# Metro Sheet Vision

On-device Optical Music Recognition for piano learners to detect accidentals in sheet music. Accidentals change a note by a semitone (sharp raises, flat lowers, natural cancels).

- Platform: iOS (min iOS 16)
- Runtime: Apple Vision + CoreML (Neural Engine)
- Model: NotA v3.0 (YOLO11n)
- MethodChannel: `com.hana.metro_sheet_vision/omr`

## Prerequisites

Make sure these are installed:

- Flutter 3.19: `flutter --version`
- Xcode 15: `xcodebuild -version`
- CocoaPods 1.14: `pod --version`
- Python 3.12: `python3.12 --version`

Python 3.12 is required for `coremltools 8.x`. Python 3.13/3.14 is not supported.

## Model source

The default model is downloaded in the conversion script from:

- https://github.com/v-dvorak/omr-layout-analysis
- https://github.com/v-dvorak/omr-layout-analysis/releases

## App flow and screenshots

Start from the home screen.
placeholder

If the user taps **Scan**, the app will show scan screen like this for scanning. 
placeholder
placeholder

If the user taps **Choose from library**, the app will show the picker screen.
placeholder

After an image is selected, the app will show the buffering state "Analyzing sheet music".
placeholder

then the app will show the results with detected accidentals, both are the default result and when it is zoomed.
placeholder
placeholder

Next, if the specific accidental is pressed, accidental detail popups for Flat, Natural, and Sharp will be shown.
placeholder x 3

Finally, the app will show the detections detail panel pulled up from the bottom.
placeholder

## How to run

### 1) Clone and install Flutter deps

```bash
git clone https://github.com/citylighxts/metro_sheet_vision
cd metro_sheet_vision
flutter pub get
```

### 2) Install iOS pods

```bash
cd ios && pod install && cd ..
```

Open `ios/Runner.xcworkspace` (not `Runner.xcodeproj`).

### 3) Convert the OMR model to CoreML

#### 3.1 Create a Python 3.12 venv

```bash
/opt/homebrew/bin/python3.12 -m venv .venv312
source .venv312/bin/activate
python --version
```

#### 3.2 Install Python deps

```bash
pip install -r scripts/requirements.txt
```

#### 3.3 Run conversion

```bash
python scripts/convert_omr_model.py --model nota
```

Output should include:

```
build/MetroSheetOMR.mlmodelc
build/omr_labels.json
```

### 4) Add the model to Xcode

1. Open Xcode:

```bash
open ios/Runner.xcworkspace
```

2. In Xcode, right-click **Runner** → **Add Files to "Runner"...**
3. Select `build/MetroSheetOMR.mlmodelc`
4. Check **Copy items if needed** and **Add to target: Runner**

### 5) Configure signing

1. Select **Runner** project
2. **Signing & Capabilities** → set your Team
3. Set a unique Bundle ID

### 6) Run the app (real device)

Simulator does not use the Neural Engine.

```bash
flutter run --release
```

To select a device:

```bash
flutter devices
flutter run --release -d <device-id>
```