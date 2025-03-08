# 🎯 AI Resume Tailoring

An automated system that tailors your resume to specific job descriptions using Google's Gemini AI, ensuring the best match between your qualifications and employer requirements.

## 📋 Project Overview

This project provides a seamless workflow to customize your resume for job applications by:

1. Analyzing a job description using Google's Gemini AI
2. Automatically tailoring your resume content to highlight relevant skills and experiences
3. Generating a professionally formatted PDF using LaTeX

## ✨ Features

- **🧠 AI-Powered Tailoring**: Leverages Google's Gemini AI to analyze job descriptions and tailor your resume
- **📄 LaTeX PDF Generation**: Creates professionally formatted PDF resumes using LaTeX
- **🚀 Easy to Use**: Simple batch script execution for Windows users
- **🔧 Customizable**: Maintains the original LaTeX structure while optimizing content

## 📦 Requirements

### 💻 Software Requirements
- Python 3.6 or higher
- LaTeX distribution (such as MiKTeX) with pdflatex compiler
- PowerShell 5.0 or higher
- Google Gemini API key

### 📚 Python Packages
- google-generativeai

## 🔧 Installation

1. **📥 Clone or download this repository**
   ```powershell
   git clone <repository-url>
   # Or download and extract the ZIP file
   ```

2. **🐍 Install Python**
   ```powershell
   # Download from https://www.python.org/downloads/
   # After installation, verify with:
   python --version
   ```

3. **📑 Install LaTeX**
   ```powershell
   # Download and install MiKTeX from: https://miktex.org/download
   # After installation, verify with:
   pdflatex --version
   ```

4. **📦 Install the required Python package**
   ```powershell
   pip install -r requirements.txt
   ```

5. **🔑 Set up Google Gemini API Key**
   - Visit [Google AI Studio](https://aistudio.google.com/) to obtain an API key
   - Set the API key as a permanent environment variable:
     
     ```powershell
     # For permanent storage (system level, requires administrator permission)
     [System.Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "your-api-key-here", "Machine")
     ```

## 🚀 Usage

### ⚡ Quick Start (Windows)

1. **📝 Edit the job description file**
   ```powershell
   # Open JD.txt in your favorite editor
   notepad JD.txt
   # Paste the job description and save
   ```

2. **▶️ Run the tailoring script**
   ```powershell
   # Either double-click on Resume_Tailor.bat
   # Or run it from PowerShell
   .\Resume_Tailor.bat
   ```

3. **✨ Enjoy your tailored resume!**
   The script will:
   - Generate a tailored LaTeX resume
   - Compile it into a PDF
   - Open the PDF automatically

### ⚙️ Parameters

The PowerShell script accepts the following parameters:

- -JobDescriptionPath: Path to the text file containing the job description (required)
- -CompanyName: Company name (optional, will be extracted from job description if not provided)
- -PositionName: Position name (optional, will be extracted from job description if not provided)
- -GeminiApiKey: Your Google Gemini API key (optional, will use environment variable if not provided)
- -DeleteTEXFile: Whether to delete the generated .tex file after PDF creation (default: false)

## 📁 Project Structure

- myresume.tex: LaTeX template for your resume
- TailorResume.ps1: PowerShell script that manages the tailoring process
- Resume_Tailor.bat: Batch script for easy execution on Windows
- Tailor_with_gemini.py: Python script that interfaces with Google's Gemini AI
- JD.txt: File to paste the job description

## ✏️ Customizing Your Resume

1. **📄 Edit the LaTeX template**
   ```powershell
   # Open the template in your favorite editor
   notepad myresume.tex
   ```
   Update your personal information, work experience, education, and skills

2. **🧩 The AI tailoring process** will preserve your resume structure while optimizing the content for each job application


## 📄 License

This project is open source and available for personal and commercial use.
