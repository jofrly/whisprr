# installation

1. Create an [OpenRouter API Key](https://openrouter.ai/keys) & copy it
2. [Download](https://github.com/jofrly/whisprr/releases)
3. Install the app & start it
4. Click on the "Microphone" icon in the status bar and
  - Set the API-Key (Right click + Paste)
  - Set your hotkey
  - Select your audio input device
5. Press the right Cmd key to start recording, press it again to stop recording, wait until the audio is transcribed, the text will be pasted wherever your cursor currently is

# develop

    swift build
    swift run

# release

    ./create-dmg.sh
    ls Whisprr.dmg
