# 📚 Comics Scripts

This folder contains utilities for managing digital comic book archives.

## 📜 Available Scripts

### 1. `cbr_to_cbz.zsh`
A batch conversion tool that transforms `.cbr` (RAR-based) archives into `.cbz` (ZIP-based) archives.
* **Why use this?** CBZ is an open standard and generally has better support across various cross-platform readers.
* **Key Features:** 
    * High-quality compression (Level 9).
    * Handles multiple files or wildcards (e.g., `*.cbr`).
    * Uses a temporary directory to ensure extraction is clean and organized.
* **Usage:** 
    * Convert one file: `./cbr_to_cbz.zsh "Spider-Man 01.cbr"`
    * Convert everything: `./cbr_to_cbz.zsh *.cbr`

## 📦 Required Dependencies
* **p7zip (7z)**: Used for both extracting RAR files and creating ZIP archives.

## 🛠️ Installation (Arch Based / Debian Based)
```bash
sudo pacman -Syu 7zip
```
```bash
sudo apt update
sudo apt install p7zip-full
```
