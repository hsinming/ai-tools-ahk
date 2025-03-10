# AI-Tools-AHK

<a href="url"><img src="./res/AI-Tool-AHK.gif"></a><br></br>

### Table of Contents

- [What's this?](#whats-this)  
- [Installation](#installation)  
- [Usage](#usage)  
- [Options](#options)  
- [Supported APIs](#supported-apis)
- [OpenRouter API Guide](#openrouter-api-guide)
- [New Features](#new-features)
- [Compatibility](#compatibility)
- [Credits](#credits)
&nbsp;

## What's this?  

AI-Tools-AHK is a Windows tool that allows you to run custom OpenAI prompts on text in any window using global hotkeys. It provides low-friction AI text editing ("spicy autocomplete") anywhere in Windows.

**Where can it be used?**  

Almost anywhere in Windows where you can enter text.
&nbsp;  

---

## Installation  

To get started, download the latest version of the script using GitHub's built-in **Download ZIP** feature:

🔹 **[Download ZIP](https://github.com/hsinming/ai-tools-ahk/archive/refs/heads/main.zip)**

### Setup Instructions
1. **Download the ZIP file** from the link above.
2. **Extract the contents** to a folder of your choice.
3. **Ensure that [AutoHotkey v2](https://www.autohotkey.com/) is installed** on your system.
4. **Run `AI-Tools.ahk`** by double-clicking the file.

When you run the script for the first time, it will create a `settings.ini` file in the same directory. This file contains the script's settings, which you can edit to customize the hotkeys, API preferences, and prompts.

Additionally, the script will prompt you to enter your **OpenRouter API key** or **OpenAI API key** if you haven't set one yet. Refer to the [OpenRouter API Guide](#openrouter-api-guide) or [OpenAI](https://platform.openai.com/) for instructions on obtaining an API key.

---

## Usage

The default hotkeys and prompts are set to the following:

- `Ctrl+Alt+j` - (Auto-select text - Brief history summary) - Auto selects the current line or paragraph and runs the "Brief history summary" prompt.
- `Ctrl+Alt+k` - (Auto-select text - Prompt Menu) - Auto selects the current line or paragraph and opens the prompt menu.
- `Ctrl+Alt+l` - (Manual-select text - Prompt Menu) - Opens the prompt menu to pick the prompt to run on the selected text.

---

## Options

The `settings.ini` file contains the settings for the script. You can edit this file to change the prompts, the API mode and model to use, and individual model settings.

**Start with Windows**  

To have the script start when Windows boots up, select "Start With Windows" from the tray icon.  
&nbsp;

---

## Supported APIs

This tool supports multiple AI APIs:

- **OpenAI API**
- **OpenRouter API** (default)

### Available Models
| API Provider | Supported Models |
|-------------|----------------|
| **OpenAI**  | `gpt-4o`, `gpt-4o-mini`, `gpt-*` |
| **OpenRouter**  | Various models (see OpenRouter API docs) |

---

## OpenRouter API Guide

By default, this tool uses **OpenRouter API**, a gateway that allows you to access multiple AI models through a single API key.

### How to Get an OpenRouter API Key
1. **Go to OpenRouter API website:** [https://openrouter.ai/](https://openrouter.ai/)
2. **Sign up and log in.**
3. **Navigate to "API Keys" section** and generate a new API key.
4. **Copy the API key** and paste it into the tool when prompted.
5. **You're all set!** 🎉

---

## New Features

This release introduces several new enhancements:

### 1️⃣ Radiology-Specific Prompts
- Added multiple **radiologist-friendly prompts**.
- Streamlines **report generation, standardization, and AI-assisted suggestions**.
- Prompts include:
  - **Brief History Summary**: Summarizes clinical information into concise, telegraphic summaries to aid in generating accurate and relevant radiology reports.
  - **Detailed History Summary**: Extracts the most critical clinical details that directly impact radiology interpretation.
  - **Translate to Chinese**: Translates medical English texts into Traditional Chinese, adhering to official regulations and standard terminology used in Taiwan.
  - **Rewrite as Radiologist**: Rewrites text as if dictated by a radiologist, adding relevant insights based on radiology knowledge and experience.
  - **Generate Impression**: Summarizes clinically significant findings in the imaging report into an Impression section.
  - **Complete Report**: Completes partial radiology reports by adding missing findings based on best practices.
  - **Next Sentence**: Predicts and generates the most likely next sentence in a radiology report.
  - **Structured Report**: Transforms free-text radiology reports into structured, concise, and professional reports.
  - **Free Text Report**: Converts structured radiology reports into concise, formal free-text radiology reports.
  - **Differential Diagnosis**: Provides plausible differential diagnoses for clinically important and abnormal findings.
  - **Staging Lung Cancer**: Analyzes imaging reports to determine the correct TNM stage for lung cancer according to the AJCC 9th edition TNM classification.

### 2️⃣ Support for OpenRouter APIs
- OpenRouter is now the **default API provider**.

### 3️⃣ Response Pop-Up with Tabbed View
- The response window now has **two tabs**:
  1. **Web View** - Displays responses in formatted HTML.
  2. **Text View** - Displays plain text output.
- **New "Copy" button** allows one-click copying of responses.

---

## Compatibility

Tested on Windows 10 Pro 22H2 64-bit.

---

## Credits  

This project would not have been possible without the contributions and resources provided by the following developers and the AutoHotkey community. Special thanks to:  

- **ecornell** for the original [ai-tools-ahk](https://github.com/ecornell/ai-tools-ahk), which inspired key components of this project.  
- **TheArkive** for [JXON_ahk2](https://github.com/TheArkive/JXON_ahk2) and [M-ArkDown_ahk2](https://github.com/TheArkive/M-ArkDown_ahk2), which enable efficient JSON parsing and Markdown rendering in AHK v2.  
- **iseahound** for [SetSystemCursor](https://github.com/iseahound/SetSystemCursor), a useful library for customizing system cursors.  
- **The AutoHotkey Community** for their continuous support, discussions, and shared knowledge, which have greatly contributed to the improvement of this project.  

🙏 Thank you all for your contributions!
