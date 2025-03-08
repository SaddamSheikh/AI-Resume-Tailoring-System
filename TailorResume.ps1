<#
.SYNOPSIS
    Automates the process of tailoring a resume based on a job description using Gemini AI.

.DESCRIPTION
    This script creates a tailored resume by:
    1. Creating a new .tex file based on the provided company and position names
    2. Copying content from the myresume.tex template
    3. Using Gemini AI to tailor the resume content based on the job description
    4. Compiling the .tex file into a PDF using MiKTeX's pdflatex

.PARAMETER JobDescriptionPath
    Path to the text file containing the job description
    
.PARAMETER GeminiApiKey
    Your Google Gemini API key. If not provided, the script will check for a GEMINI_API_KEY environment variable

.PARAMETER DeleteTEXFile
    When set to $true, the script will delete the generated .tex file after successful PDF creation.
    Default is $false, which keeps the .tex file for future reference or editing.

.EXAMPLE
    .\\TailorResume.ps1 -JobDescriptionPath \".\\JD.txt\"
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$JobDescriptionPath,
    
    [Parameter(Mandatory=$false)]
    [string]$CompanyName = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$PositionName = $null,
    
    [Parameter(Mandatory=$false)]
    [string]$GeminiApiKey,
    
    [Parameter(Mandatory=$false)]
    [bool]$DeleteTEXFile = $false
)

# Check if Python is installed
function Test-PythonInstalled {
    try {
        $pythonVersion = python --version 2>&1
        Write-Host "Python is installed: $pythonVersion" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Python is not installed or not in PATH. Please install Python 3.6 or higher." -ForegroundColor Red
        return $false
    }
}

# Check if a Python package is installed
function Test-PythonPackage {
    param ([string]$packageName)
    
    $checkCommand = "python -c 'import $packageName' 2>&1"
    $result = Invoke-Expression $checkCommand
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Package '$packageName' is installed." -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "Package '$packageName' is not installed." -ForegroundColor Yellow
        return $false
    }
}

# Install a Python package if not already installed
function Install-PythonPackage {
    param ([string]$packageName)
    
    if (-not (Test-PythonPackage $packageName)) {
        Write-Host "Installing package '$packageName'..." -ForegroundColor Yellow
        $installCommand = "pip install $packageName"
        
        try {
            Invoke-Expression $installCommand 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Successfully installed '$packageName'." -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "Failed to install '$packageName'." -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "Error installing '$packageName': $_" -ForegroundColor Red
            return $false
        }
    }
    return $true
}

# Get or set Gemini API key
function Get-GeminiApiKey {
    param ([string]$providedKey)
    
    # If key is provided as parameter, use it
    if ($providedKey) {
        return $providedKey
    }
    
    # Check for environment variable
    $envKey = [Environment]::GetEnvironmentVariable("GEMINI_API_KEY")
    if ($envKey) {
        Write-Host "Using Gemini API key from environment variable." -ForegroundColor Green
        return $envKey
    }
    
    # Prompt for key if not found
    Write-Host "Gemini API key not found. Please enter your API key:" -ForegroundColor Yellow
    $secureKey = Read-Host -Prompt "Gemini API key" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $key = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    # Store in user environment variable for future use
    [Environment]::SetEnvironmentVariable("GEMINI_API_KEY", $key, "User")
    Write-Host "Gemini API key has been saved to your user environment variables." -ForegroundColor Green
    
    return $key
}

function Fix-LaTeXSpecialChars {
    param ([string]$text)
    
    # Replace LaTeX special characters with their escaped versions
    $text = $text -replace '&', '\&'
    $text = $text -replace '%', '\%'
    $text = $text -replace '\$', '\$'
    $text = $text -replace '#', '\#'
    $text = $text -replace '_', '\_'
    $text = $text -replace '\{', '\{'
    $text = $text -replace '\}', '\}'
    $text = $text -replace '~', '\textasciitilde{}'
    $text = $text -replace '\^', '\textasciicircum{}'
    $text = $text -replace '\\', '\textbackslash{}'
    
    return $text
}

function Create-TailoredResume {
    try {
        # 1. Check if the job description file exists
        if (-not (Test-Path $JobDescriptionPath)) {
            throw "Job description file not found at path: $JobDescriptionPath"
        }
        
        # 2. Read the job description
        $jobDescription = Get-Content -Path $JobDescriptionPath -Raw
        Write-Host "Job description loaded successfully." -ForegroundColor Green
        
        # 3. Check Python requirements
        if (-not (Test-PythonInstalled)) {
            throw "Python is required for the AI-powered resume tailoring feature."
        }
        
        # 4. Install the google-generativeai package if needed
        if (-not (Install-PythonPackage "google.generativeai")) {
            Write-Host "Warning: Unable to install the required Python package. Will proceed with manual tailoring mode." -ForegroundColor Yellow
            $useAI = $false
        } else {
            $useAI = $true
        }
        
        # 5. Get API key if using AI
        if ($useAI) {
            $apiKey = Get-GeminiApiKey $GeminiApiKey
            if (-not $apiKey) {
                Write-Host "Warning: No Gemini API key provided. Will proceed with manual tailoring mode." -ForegroundColor Yellow
                $useAI = $false
            }
        }
        
        # 3. Check if myresume.tex exists
        if (-not (Test-Path "myresume.tex")) {
            throw "Template file 'myresume.tex' not found in the current directory."
        }
                # 4. Create the new file name
                $date = try {
                    Get-Date -Format "yyyyMMdd"
                } catch {
                    Write-Host "Error formatting date: $_" -ForegroundColor Red
                    Write-Host "Debug - Get-Date output: $(Get-Date)" -ForegroundColor Yellow
                    "yyyyMMdd" # Fallback to string format if conversion fails
                }
                Write-Host "Debug - Formatted date: $date" -ForegroundColor DarkGray
                
                # Create filename based on company/position if provided, otherwise use generic name
                if ($CompanyName -and $PositionName) {
                    # Create sanitized versions with underscores for filenames
                    $sanitizedCompany = $CompanyName -replace " ", "_"
                    $sanitizedPosition = $PositionName -replace " ", "_"
                    $tempFileName = "$sanitizedCompany-$sanitizedPosition-$date.tex"
                } else {
                    $tempFileName = "AutoTailoredResume-$date.tex"
                }
                
                # 5. Copy the content from myresume.tex
                try {
                    $resumeContent = Get-Content -Path "myresume.tex" -Raw
                    Write-Host "Template loaded successfully." -ForegroundColor Green
                } catch {
                    Write-Host "Error loading template file 'myresume.tex': $_" -ForegroundColor Red
                    throw "Failed to load template file: $_"
                }
        Write-Host "Template loaded successfully." -ForegroundColor Green
        
        # 6. Add tailoring comments based on job description
        $headerComment = "% Tailored resume generated on $(Get-Date)"
        $tailoringGuide = @"
% JOB DESCRIPTION SUMMARY:
% ------------------------
% The following is a brief summary of the job description. Use this to guide your tailoring.
% 
% TAILORING GUIDE:
% ----------------
% 1. Professional Summary: Highlight your most relevant skills and experiences
% 2. Skills Section: Prioritize skills mentioned in the job description
% 3. Work Experience: Emphasize relevant accomplishments and responsibilities
% 4. Keywords: Include industry and role-specific terminology from the JD
% 5. Quantify: Add metrics and percentages where possible
%
"@

        # Insert tailoring guide after the document class declaration
        $resumeContent = $resumeContent -replace '(\\documentclass.*?\n)', "`$1`n$headerComment`n$tailoringGuide`n"

        # 7. Save the template file for processing
        $tempTemplateFile = [System.IO.Path]::GetTempFileName() + ".tex"
        $tempTemplateFile = [System.IO.Path]::GetTempFileName() + ".tex"
        $resumeContent | Out-File -FilePath $tempTemplateFile -Encoding utf8
        Write-Host "Template prepared for processing." -ForegroundColor Green
        # 8. Save job description to a temporary file
        $tempJdFile = [System.IO.Path]::GetTempFileName() + ".txt"
        $jobDescription | Out-File -FilePath $tempJdFile -Encoding utf8

        # 9. Use Gemini AI to tailor the resume if available
        if ($useAI) {
            Write-Host "Using Gemini AI to tailor your resume..." -ForegroundColor Yellow
            try {
                # Check if tailor_with_gemini.py exists in the current directory
                if (-not (Test-Path "tailor_with_gemini.py")) {
                    Write-Host "tailor_with_gemini.py not found. Creating the script..." -ForegroundColor Yellow
                    # Here you would need to create or download the script
                    throw "tailor_with_gemini.py is required but not found."
                }
                
                # Run the Python script to tailor the resume
                $env:GEMINI_API_KEY = $apiKey
                $pythonCmd = "python tailor_with_gemini.py --template `"$tempTemplateFile`" --jd `"$tempJdFile`""

                # Only add company and position parameters if provided
                if ($CompanyName) {
                    $pythonCmd += " --company `"$CompanyName`""
                }
                if ($PositionName) {
                    $pythonCmd += " --position `"$PositionName`""
                }

                # Check if newFileName is defined
                if (-not $newFileName) {
                    $newFileName = $tempFileName
                    Write-Host "Debug - Using tempFileName as newFileName was not defined: $newFileName" -ForegroundColor Yellow
                }
                $pythonCmd += " --output `"$newFileName`""
                Write-Host "Debug - Full Python command: $pythonCmd" -ForegroundColor DarkGray
                
                # Simple test to verify Python is working correctly
                try {
                    $pythonVersionTest = python -c "print('Python verification test: OK')" 2>&1
                    Write-Host "Python verification test: $pythonVersionTest" -ForegroundColor Green
                } catch {
                    Write-Host "Python verification test failed: $_" -ForegroundColor Red
                    throw "Python environment verification failed. Please check your Python installation."
                }

                # Print the exact Python command being executed
                Write-Host "Executing Python command:" -ForegroundColor Cyan
                Write-Host $pythonCmd -ForegroundColor Yellow

                # Python version test
                try {
                    # Simple test to verify Python is working correctly
                    $pythonVersionTest = python -c "print('Python verification test: OK')" 2>&1
                    Write-Host "Python verification test: $pythonVersionTest" -ForegroundColor Green
                } catch {
                    Write-Host "Python verification test failed: $_" -ForegroundColor Red
                    throw "Python environment verification failed. Please check your Python installation."
                }

                # Python execution
                try {
                    # Execute Python with detailed error capture
                    Write-Host "Starting Python script execution..." -ForegroundColor DarkGray
                    try {
                        $pythonResult = Invoke-Expression $pythonCmd 2>&1
                        
                        # Verify pythonResult is properly captured
                        if ($null -eq $pythonResult -or $pythonResult -eq "") {
                            Write-Host "Warning: Python command returned null or empty result" -ForegroundColor Yellow
                            $pythonResult = "No output from Python script"
                        }
                        
                        # Handle array results safely
                        if ($pythonResult -is [System.Array] -and $pythonResult.Count -gt 0) {
                            Write-Host "Debug - Python returned an array with $($pythonResult.Count) items" -ForegroundColor DarkGray
                            # Convert array to string to avoid indexing issues
                            $pythonResult = $pythonResult -join "`n"
                        }

                        Write-Host "Debug - Python execution result type: $($pythonResult.GetType().FullName)" -ForegroundColor DarkGray
                        Write-Host "Debug - Python execution result: $pythonResult" -ForegroundColor DarkGray
                        # More detailed error checking
                        if ($LASTEXITCODE -ne 0) {
                            Write-Host "Python script exited with code: $LASTEXITCODE" -ForegroundColor Red
                            Write-Host "Full Python error output:" -ForegroundColor Red
                            $pythonResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
                            throw "Python script execution failed with exit code $LASTEXITCODE"
                        }

                        # Extract the final filename from the Python script output
                        # Add detailed diagnostics about pythonResult
                        $resultType = if ($null -eq $pythonResult) { 'NULL' } else { $pythonResult.GetType().FullName }
                        Write-Host "Debug - pythonResult type: $resultType" -ForegroundColor DarkGray
                        if ($null -eq $pythonResult) {
                            Write-Host "Warning: pythonResult is null, cannot extract filename" -ForegroundColor Yellow
                            $newFileName = $tempFileName
                            Write-Host "Using tempFileName as fallback: $newFileName" -ForegroundColor Yellow
                        } 
                        elseif ($pythonResult -match "Tailored resume successfully saved to: (.+\.tex)") {
                            $newFileName = $matches[1]
                            Write-Host "Debug - Extracted filename from Python output: $newFileName" -ForegroundColor DarkGray
                        } else {
                            Write-Host "Debug - Could not extract filename pattern from Python output" -ForegroundColor Yellow
                            $resultOutput = if ($null -eq $pythonResult) { 'NULL' } else { $pythonResult }
                            Write-Host "Debug - Python output was: $resultOutput" -ForegroundColor Yellow
                            $newFileName = $tempFileName
                            Write-Host "Using tempFileName as fallback: $newFileName" -ForegroundColor Yellow
                        }

                        # Check pythonResult before trying to match patterns
                        if ($null -eq $pythonResult) {
                            Write-Host "Warning: pythonResult is null, cannot extract company/position" -ForegroundColor Yellow
                            if (-not $CompanyName) { $CompanyName = "Company" }
                            if (-not $PositionName) { $PositionName = "Position" }
                        }
                        # Match against the first pattern: "Extracted Company: X\nExtracted Position: Y"
                        elseif ($pythonResult -match "Extracted Company: (.+)\r?\nExtracted Position: (.+)") {
                            $extractedCompany = $matches[1].Trim()
                            $extractedPosition = $matches[2].Trim()
                            Write-Host "Debug - Extracted company: $extractedCompany, position: $extractedPosition" -ForegroundColor DarkGray
                            
                            # Create sanitized versions with underscores for filenames
                            $sanitizedCompany = $extractedCompany -replace " ", "_"
                            $sanitizedPosition = $extractedPosition -replace " ", "_"
                            Write-Host "Debug - Sanitized names: $sanitizedCompany, $sanitizedPosition" -ForegroundColor DarkGray
                            
                            # If company/position wasn't provided, use the extracted values
                            if (-not $CompanyName) {
                                $CompanyName = $extractedCompany
                                Write-Host "AI extracted company name: $CompanyName" -ForegroundColor Green
                            }
                            if (-not $PositionName) {
                                $PositionName = $extractedPosition
                                Write-Host "AI extracted position name: $PositionName" -ForegroundColor Green
                            }
                            
                            # Update tempFileName and newFileName with sanitized extracted information
                            $tempFileName = "$sanitizedCompany-$sanitizedPosition-$date.tex"
                            Write-Host "Debug - Updated tempFileName with extracted information: $tempFileName" -ForegroundColor DarkGray
                            
                            # Store the original generated filename before updating it
                            $originalFileName = $newFileName
                            $newFileName = $tempFileName
                            Write-Host "Debug - Updated newFileName with extracted information: $newFileName" -ForegroundColor Green
                            
                            # If the original file exists but doesn't match our new desired filename, copy/rename it
                            if (Test-Path $originalFileName) {
                                Write-Host "Debug - Found Python-generated file: $originalFileName" -ForegroundColor Green
                                if ($originalFileName -ne $newFileName) {
                                    Write-Host "Renaming Python-generated file from $originalFileName to $newFileName" -ForegroundColor Yellow
                                    Copy-Item -Path $originalFileName -Destination $newFileName -Force
                                }
                            } else {
                                Write-Host "Warning: Python-generated file $originalFileName not found" -ForegroundColor Yellow
                            }
                        }
                        # Match against the alternative pattern with escaped characters
                        elseif ($pythonResult -match "Extracted Company: (.+)\\r?\\nExtracted Position: (.+)") {
                            $extractedCompany = $matches[1].Trim()
                            $extractedPosition = $matches[2].Trim()
                            Write-Host "Debug - Extracted company: $extractedCompany, position: $extractedPosition" -ForegroundColor DarkGray
                            
                            # Create sanitized versions with underscores for filenames
                            $sanitizedCompany = $extractedCompany -replace " ", "_"
                            $sanitizedPosition = $extractedPosition -replace " ", "_"
                            Write-Host "Debug - Sanitized names: $sanitizedCompany, $sanitizedPosition" -ForegroundColor DarkGray
                            
                            # If company/position wasn't provided, use the extracted values
                            if (-not $CompanyName -and $extractedCompany -ne "Unknown Company") {
                                $CompanyName = $extractedCompany
                                Write-Host "AI extracted company name: $CompanyName" -ForegroundColor Green
                            }
                            if (-not $PositionName -and $extractedPosition -ne "Unknown Position") {
                                $PositionName = $extractedPosition
                                Write-Host "AI extracted position name: $PositionName" -ForegroundColor Green
                            }
                            
                            # Update tempFileName and newFileName with sanitized extracted information
                            $tempFileName = "$sanitizedCompany-$sanitizedPosition-$date.tex"
                            Write-Host "Debug - Updated tempFileName with extracted information: $tempFileName" -ForegroundColor DarkGray
                            
                            # Store the original generated filename before updating it
                            $originalFileName = $newFileName
                            $newFileName = $tempFileName
                            Write-Host "Debug - Updated newFileName with extracted information: $newFileName" -ForegroundColor Green
                            
                            # If the original file exists but doesn't match our new desired filename, copy/rename it
                            if (Test-Path $originalFileName) {
                                Write-Host "Debug - Found Python-generated file: $originalFileName" -ForegroundColor Green
                                if ($originalFileName -ne $newFileName) {
                                    Write-Host "Renaming Python-generated file from $originalFileName to $newFileName" -ForegroundColor Yellow
                                    Copy-Item -Path $originalFileName -Destination $newFileName -Force
                                }
                            } else {
                                Write-Host "Warning: Python-generated file $originalFileName not found" -ForegroundColor Yellow
                            }
                        }
                        
                        # If gemini-pro is not found, it's likely using gemini-1.5-pro
                        if ($null -ne $pythonResult -and $pythonResult -match "models/gemini-pro is not found") {
                            Write-Host "Note: Using gemini-1.5-pro model instead of gemini-pro" -ForegroundColor Yellow
                        }
                        
                        Write-Host "Resume tailored successfully with Gemini AI." -ForegroundColor Green
                    } catch {
                        Write-Host "Error executing Python command:" -ForegroundColor Red
                        Write-Host $_ -ForegroundColor Red
                        throw "Python execution failed: $_"
                    }
                } catch {
                    Write-Host "Error using Gemini AI: $_" -ForegroundColor Red
                    Write-Host "Falling back to template-only approach..." -ForegroundColor Yellow
                    
                    $resumeContent | Out-File -FilePath $tempFileName -Encoding utf8
                    $newFileName = $tempFileName
                    Write-Host "Created resume file from template: $newFileName" -ForegroundColor Green
                }
            } catch {
                Write-Host "Error in AI tailoring process: $_" -ForegroundColor Red
                Write-Host "Falling back to template-only approach..." -ForegroundColor Yellow
                
                $resumeContent | Out-File -FilePath $tempFileName -Encoding utf8
                $newFileName = $tempFileName
                Write-Host "Created resume file from template: $newFileName" -ForegroundColor Green
            }
        } else {
            # Standard approach without AI
            $resumeContent | Out-File -FilePath $tempFileName -Encoding utf8
            $newFileName = $tempFileName
            Write-Host "Created new resume file: $newFileName" -ForegroundColor Green
        }
        
        # 8. Compile the LaTeX file
        Write-Host "Compiling LaTeX file to PDF..." -ForegroundColor Yellow

        # Verify the file exists before trying to compile it
        if (Test-Path $newFileName) {
            Write-Host "Debug - File to compile exists: $newFileName" -ForegroundColor Green
        } else {
            Write-Host "Warning: File to compile does not exist: $newFileName" -ForegroundColor Red
            
            # Look for the AutoTailoredResume file as fallback
            $fallbackFile = "AutoTailoredResume-$date.tex"
            if (Test-Path $fallbackFile) {
                Write-Host "Found fallback file to compile: $fallbackFile" -ForegroundColor Yellow
                $newFileName = $fallbackFile
            } else {
                Write-Host "Error: Neither target file nor fallback file exists. Cannot compile." -ForegroundColor Red
                return $false
            }
        }

        Write-Host "Attempting to compile file: $newFileName" -ForegroundColor Cyan
        $process = Start-Process -FilePath "pdflatex" -ArgumentList "-interaction=nonstopmode", "`"$newFileName`"" -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Host "Warning: Initial compilation may have issues. Attempting second pass..." -ForegroundColor Yellow
            # Second compilation pass to resolve references
            $process = Start-Process -FilePath "pdflatex" -ArgumentList "-interaction=nonstopmode", "`"$newFileName`"" -NoNewWindow -Wait -PassThru
        }
        
        # 9. Check if PDF was created
        try {
            if (-not $newFileName) {
                Write-Host "Error: newFileName variable is null or empty" -ForegroundColor Red
                $newFileName = "AutoTailoredResume-$date.tex"
                Write-Host "Using fallback filename: $newFileName" -ForegroundColor Yellow
            }
            $pdfFileName = $newFileName -replace "\.tex$", ".pdf"
            Write-Host "Debug - PDF filename: $pdfFileName" -ForegroundColor DarkGray
        } catch {
            Write-Host "Error creating PDF filename: $_" -ForegroundColor Red
            $pdfFileName = "AutoTailoredResume-$date.pdf"
            Write-Host "Using fallback PDF filename: $pdfFileName" -ForegroundColor Yellow
        }
        if (Test-Path $pdfFileName) {
            Write-Host "PDF file created successfully: $pdfFileName" -ForegroundColor Green
            
            # Open the PDF file with the default PDF viewer
            Write-Host "Opening PDF file..." -ForegroundColor Yellow
            try {
                Invoke-Item $pdfFileName
                Write-Host "PDF file opened successfully." -ForegroundColor Green
            } catch {
                Write-Host "Warning: Could not open PDF file automatically: $_" -ForegroundColor Yellow
                Write-Host "Please open the file manually: $pdfFileName" -ForegroundColor Yellow
            }
            
            # Clean up auxiliary LaTeX files after successful PDF generation
            Write-Host "Cleaning up auxiliary files..." -ForegroundColor Yellow
            $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($newFileName)
            $auxFiles = @(
                "$baseFileName.log",
                "$baseFileName.aux", 
                "$baseFileName.out",
                "$baseFileName.synctex.gz",
                "$baseFileName.fls",
                "$baseFileName.fdb_latexmk"
            )

            # Add TEX file to cleanup list if DeleteTEXFile is true
            # Add TEX file to cleanup list if DeleteTEXFile is true
            if ($DeleteTEXFile -eq $true) {
                $auxFiles += "$baseFileName.tex"
                Write-Host "TEX file will also be deleted as requested." -ForegroundColor Yellow
            }
            
            foreach ($file in $auxFiles) {
                if (Test-Path $file) {
                    Remove-Item $file -Force
                    Write-Host "  Removed: $file" -ForegroundColor DarkGray
                }
            }
            Write-Host "Cleanup completed." -ForegroundColor Green
        } else {
            Write-Host "Warning: PDF file might not have been created properly." -ForegroundColor Yellow
        }
        # 10. Clean up temporary files
        if (Test-Path $tempTemplateFile) { Remove-Item $tempTemplateFile -Force }
        if (Test-Path $tempJdFile) { Remove-Item $tempJdFile -Force }

        # 11. Generate summary of what was done
        Write-Host "`nSummary of Actions:" -ForegroundColor Cyan
        Write-Host "1. Created new LaTeX file: $newFileName" -ForegroundColor White
        Write-Host "2. Copied content from myresume.tex" -ForegroundColor White

        if ($useAI) {
            Write-Host "3. Used Gemini AI to tailor the resume based on the job description" -ForegroundColor White
            Write-Host "4. Compiled the LaTeX file to PDF: $pdfFileName" -ForegroundColor White
            
            Write-Host "`nNext Steps:" -ForegroundColor Cyan
            Write-Host "1. Review the AI-tailored resume in $pdfFileName" -ForegroundColor White
            Write-Host "2. Make any final adjustments in $newFileName if needed" -ForegroundColor White
            Write-Host "3. Recompile after making changes using: pdflatex $newFileName" -ForegroundColor White
        } else {
            Write-Host "3. Added tailoring guidelines based on job description" -ForegroundColor White
            Write-Host "4. Compiled the LaTeX file to PDF: $pdfFileName" -ForegroundColor White
Write-Host "`nNext Steps:" -ForegroundColor Cyan 
Write-Host "1. Open $newFileName in your LaTeX editor" -ForegroundColor White 
Write-Host "2. Tailor the following sections based on the job description:" -ForegroundColor White 
Write-Host "   - Professional summary" -ForegroundColor White 
Write-Host "   - Skills section (prioritize relevant skills)" -ForegroundColor White 
Write-Host "   - Work experience bullet points" -ForegroundColor White 
Write-Host "3. Recompile after making changes using: pdflatex `"$newFileName`"" -ForegroundColor White 
}

            return $true
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        return $false
    }
}

# Main script execution
if ($CompanyName -and $PositionName) {
    Write-Host "Starting resume tailoring process for $PositionName at $CompanyName" -ForegroundColor Cyan
} else {
    Write-Host "Starting resume tailoring process with automatic company/position detection..." -ForegroundColor Cyan
}

# Create the tailored resume
$result = Create-TailoredResume

if ($result) {
    Write-Host "`nResume tailoring process completed successfully." -ForegroundColor Green
} else {
    Write-Host "`nResume tailoring process encountered errors." -ForegroundColor Red
    Write-Host "Please check the error messages above and try again." -ForegroundColor Red
}
