# Relat it

Relat it is the first project from **Relay Lab**.  
It is a macOS note-and-capture workspace that helps you collect screenshots, extract key information, and turn that context into organized notes with AI-assisted writing.

## What this project does

- Captures screenshots directly from your workflow.
- Extracts and structures information from captured content.
- Lets you build session-based notes in a lightweight markdown editor.
- Supports inline AI assistance for summarizing, rewriting, and continuing note content.
- Keeps note and context history connected to each session.

## Architecture overview

- **Frontend:** Native macOS app built with SwiftUI.
- **State & data flow:** ViewModels + shared app state for session, note, and capture workflows.
- **AI/API layer:** Calls a dedicated backend for analysis, summarization, and chat-style note operations.

## Backend

This app uses the following backend service repository:

- [Relay-it-api (GitHub)](https://github.com/Gary0302/Relay-it-api)

## Relay Lab

Relat it is the starting point for Relay Lab's product line.  
The goal is to make capture -> understanding -> note creation feel fast and natural for daily work.
