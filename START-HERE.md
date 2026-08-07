# Start here

1. Create a new empty GitHub repository.
2. Extract this ZIP.
3. Upload everything **inside** the extracted folder to the repository root.
4. Confirm `.github/workflows/build-unsigned-ipa.yml` exists.
5. Open **Actions > Build BudControl IPA > Run workflow**.
6. After the green check, download **BudControl-unsigned-IPA** from Artifacts.
7. Extract the artifact and install `BudControl-unsigned.ipa` with Sideloadly.

## First Finder capture

1. Connect Moto Buds+.
2. Open **Finder**.
3. Choose **Noise control cycle**.
4. Tap **1. Prepare Baseline** and wait for **Baseline ready**.
5. Tap **2. Start Action Capture**.
6. Press and hold the **right** earbud touch area for about 3 seconds until the noise mode changes.
7. Wait about 3 seconds.
8. Tap **3. Analyze Changes**.
9. Open the strongest candidate and save it as an observation.
10. Repeat the same test and look for the same service, characteristic, and byte pattern.

A repeated observation tells you which characteristic reflects an action. It does not automatically reveal the write command used by Motorola's Android app.
