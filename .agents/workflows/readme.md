---
description: Generate a beautiful, premium-quality README.md for any project
---

# README Generator Workflow

## When To Use
Use this workflow when the user asks for a README, uses `/readme`, or says "write a readme" for any project.

## Pre-Steps (Research)

1. **Scan the project** — list all files, read main scripts/source files, understand what the project does
2. **Identify each tool/module** — name, purpose, key features, CLI parameters, usage patterns
3. **Check for existing README** — if one exists, ask the user if they want to replace or enhance it
4. **Check for install/setup scripts** — document the installation flow

## README Structure Template

The README MUST follow this exact structure, in this order. Every section is mandatory unless marked optional.

---

### 1. Header Block (centered HTML)

```markdown
<p align="center">
  <img src="https://img.shields.io/badge/Platform-{PLATFORM}-{COLOR}?style=for-the-badge&logo={LOGO}&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Language-{LANG}-{COLOR}?style=for-the-badge&logo={LOGO}&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/License-{LICENSE}-green?style=for-the-badge" alt="License">
</p>

<h1 align="center">{EMOJI} {PROJECT NAME}</h1>

<p align="center">
  <b>{One-liner description of the project}</b><br>
  <sub>{Short action-oriented tagline}</sub>
</p>
```

**Badge rules:**
- Always include Platform, primary Language/Runtime, and License
- Use shields.io `for-the-badge` style
- Pick colors that match the tech stack (e.g. PowerShell=5391FE, Python=3776AB, Node=339933, Rust=DEA584)
- Use official logos from shields.io

---

### 2. Overview Table

```markdown
## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| {EMOJI} | **[Tool Name](#anchor)** | One-line description |
```

- One row per tool/module in the project
- Use relevant emoji per tool type (🔁 restart/cycle, 📂 files, 🔒 security, ⚡ performance, etc.)
- Link to the detailed section below using anchor links

---

### 3. Tool Detail Sections (repeat for each tool)

For each tool, create a section with this structure:

```markdown
## {EMOJI} {Tool Name}

> {One-sentence elevator pitch in blockquote}

### The Problem

- Bullet list of 2-4 problems this tool solves
- Be specific about pain points

### The Solution

{Brief explanation of the approach}

```
{ASCII diagram showing the flow/architecture if applicable}
```

{One sentence explaining WHY this approach is better}

### Usage

**From {primary interface}** — {step-by-step in italics}

**From terminal:**

```{language}
# Example 1 — most common use case
{command}

# Example 2 — with options
{command with flags}
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `{param}` | `{type}` | {default} | {description} |
```

**Rules for tool sections:**
- Start with blockquote elevator pitch
- Problem section: 2-4 bullet points, real pain points
- Solution section: include ASCII flow diagram when possible
- Usage: show both GUI and CLI paths
- Parameter table: every parameter, with type, default, and description
- Code examples: at least 2, with descriptive comments

---

### 4. Installation Section

```markdown
## 📦 Installation

### Quick Setup

```{language}
# Install
{install command}

# Verify
{verify command}

# Uninstall (if applicable)
{uninstall command}
```

### Requirements

| Requirement | Details |
|-------------|---------|
| **{req}** | {details} |
```

---

### 5. Project Structure

```markdown
## 📁 Project Structure

```
ProjectName/
├── file1.ext          # Short description
├── file2.ext          # Short description
├── subdir/
│   └── file3.ext      # Short description
└── README.md          # You are here
```
```

- Include ALL project files (except .git, node_modules, etc.)
- Add inline comment for each file
- Use tree-style formatting with box-drawing characters

---

### 6. Technical Notes (optional but recommended)

```markdown
## 🧠 Technical Notes

<details>
<summary><b>{Question format title}</b></summary>

{2-3 sentence explanation with **bold** keywords}

</details>
```

- Use `<details>` collapsible sections
- Title should be a question (e.g. "Why VBS launchers?", "How does caching work?")
- 2-4 sections covering non-obvious design decisions
- Keep explanations concise (2-3 sentences each)

---

### 7. Footer

```markdown
---

<p align="center">
  <sub>{tagline} · {key selling point} · {key constraint or note}</sub>
</p>
```

---

## Design Rules (MANDATORY)

1. **Premium feel** — the README should look professional and polished on GitHub
2. **Emoji consistency** — use emoji for section headers, table items, and inline highlights, but don't overdo it
3. **Tables over lists** — prefer tables for structured data (features, parameters, requirements)
4. **Code blocks always tagged** — always specify the language (`powershell`, `python`, `bash`, etc.)
5. **Anchor links** — overview table links to detail sections
6. **No placeholder text** — every section must have real, accurate content from the actual project
7. **Collapsible for deep dives** — use `<details>` for technical explanations that most users don't need
8. **Short paragraphs** — max 2-3 sentences per paragraph
9. **ASCII flow diagrams** — for explaining architecture or data flow, use simple ASCII art in code blocks
10. **Centered header and footer** — use HTML `<p align="center">` for visual balance

## Quality Checklist

Before delivering, verify:
- [ ] All badges render correctly (valid shields.io URLs)
- [ ] All anchor links work (lowercase, hyphens for spaces)
- [ ] Every CLI parameter is documented
- [ ] Code examples are copy-pasteable and correct
- [ ] File tree matches actual project structure
- [ ] No placeholder or lorem ipsum text
- [ ] Grammar and spelling are correct (use English for README)
