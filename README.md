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

<img width="201" alt="home-screen" src="https://github.com/user-attachments/assets/c9e7f4cc-5438-4c9a-9e78-c6a804359a7c" />


If the user taps **Scan**, the app will show scan screen like this for scanning. 
<p>
  <img src="https://github.com/user-attachments/assets/79bd9fde-f69d-4bda-b4f4-889f73026630" width="201" />
  &nbsp;
  <img src="https://github.com/user-attachments/assets/97178d42-7fc4-45b1-854b-434a72eaab58" width="201" />
</p>

If the user taps **Choose from library**, the app will show the picker screen.

<img width="201" alt="picker" src="https://github.com/user-attachments/assets/ef383439-cf6c-42e3-bc55-4473554c8b09" />


After an image is selected, the app will show the buffering state "Analyzing sheet music".

<img width="201" alt="buffer" src="https://github.com/user-attachments/assets/83485031-564a-42b0-a49d-ea8c0cbdf836" />


then the app will show the results with detected accidentals, both are the default result and when it is zoomed.
<p>
  <img src="https://github.com/user-attachments/assets/a57f99d9-f69b-4aa3-9dd4-0cfee2c1d427" width="201" alt="result" />
  &nbsp;
  <img src="https://github.com/user-attachments/assets/7f7c48af-ec3d-42c7-a2c9-7ead444d2a32" width="201" alt="zoomed-result" />
</p>


Next, if the specific accidental is pressed, accidental detail popups for Flat, Natural, and Sharp will be shown.
<p>
  <img src="https://github.com/user-attachments/assets/f50c79b0-1476-41b0-9b81-a314acc77cab" width="201" alt="flat-popup" />
  &nbsp;
  <img src="https://github.com/user-attachments/assets/3f5e76a4-8589-4d40-b1ab-792d5a2cc924" width="201" alt="natural-popup" />
  &nbsp;
  <img src="https://github.com/user-attachments/assets/229e2fa2-65f1-43c4-81a7-f9f009d4c0a0" width="201" alt="sharp-popup" />
</p>


Finally, the app will show the detections detail panel pulled up from the bottom.

<img width="201" alt="detail" src="https://github.com/user-attachments/assets/a3708de2-f42e-4fb5-b18d-538665667810" />


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
