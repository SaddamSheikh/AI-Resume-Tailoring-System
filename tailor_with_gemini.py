#!/usr/bin/env python
"""
tailor_with_gemini.py - Tailor resumes using Google's Gemini AI

This script takes a LaTeX resume template and a job description, then uses Gemini AI
to tailor the resume content to better match the job requirements while maintaining
the LaTeX structure.
"""

import argparse
import sys
import time
import re
import os
import json
from typing import Dict, Tuple, Optional, Any, Callable, TypeVar

# Check if the google.generativeai package is installed
try:
    import google.generativeai as genai
except ImportError:
    print("The 'google-generativeai' package is not installed.")
    print("Please install it using: pip install google-generativeai")
    sys.exit(1)


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Tailor a LaTeX resume using Gemini AI based on a job description"
    )
    parser.add_argument(
        "--template", 
        required=True, 
        help="Path to the resume template (.tex file)"
    )
    parser.add_argument(
        "--jd", 
        required=True, 
        help="Path to the job description file"
    )
    parser.add_argument(
        "--company", 
        required=False, 
        help="Company name (will be extracted from job description if not provided)"
    )
    parser.add_argument(
        "--position", 
        required=False, 
        help="Position name (will be extracted from job description if not provided)"
    )
    parser.add_argument(
        "--output", 
        required=True, 
        help="Output file path for tailored resume"
    )
    return parser.parse_args()


def setup_gemini_api(api_key: str) -> None:
    """Initialize the Gemini API with the provided key."""
    try:
        genai.configure(api_key=api_key)
        print("Gemini API configured successfully.")
    except Exception as e:
        print(f"Failed to configure Gemini API: {str(e)}")
        sys.exit(1)


def list_available_models() -> str:
    """
    List all available Gemini models and return the best available model for text generation.
    
    Returns:
        The model name to use for generation
    """
    try:
        print("Listing available Gemini models:")
        models = genai.list_models()
        
        # Print all available models for diagnostic purposes
        available_models = []
        for model in models:
            model_name = model.name
            print(f"- {model_name}")
            available_models.append(model_name)
        
        # First, check for our preferred models in a specific order
        preferred_models = [
            "models/gemini-1.5-flash" , # Our top choice
            "models/gemini-pro",   # First fallback
            "models/gemini-1.5-pro" # Second fallback
        ]
        
        # Try each preferred model first
        for preferred in preferred_models:
            if preferred in available_models:
                # Extract the model name without the "models/" prefix for API use
                short_name = preferred.split('/')[-1]
                print(f"Using preferred model: {short_name}")
                return short_name
        
        # If none of the preferred models are available, look for any text generation model
        # Try models in the same order as our FALLBACK_MODELS list
        for model_name in available_models:
            if "gemini" in model_name and not "vision" in model_name:
                # Extract the model name without the "models/" prefix
                short_name = model_name.split('/')[-1]
                print(f"Using alternative model: {short_name}")
                return short_name
        
        # If no suitable model found
        print("Warning: No suitable Gemini text generation models found!")
        print("Please check your API key permissions and try again.")
        sys.exit(1)
        
    except Exception as e:
        print(f"Error listing models: {str(e)}")
        print("Attempting to use gemini-1.5-pro as fallback...")
        return "gemini-1.5-pro"
def retry_with_models(func: Callable, model: Any, *args, **kwargs) -> Any:
    """
    Try to execute a function with a model, falling back to alternative models if quota exceeded.
    
    Args:
        func: The function to execute with the model
        model: The primary model to try first
        *args, **kwargs: Additional arguments to pass to the function
        
    Returns:
        The result of the function execution
        
    Raises:
        Exception: If all models fail
    """
    # List of models to try in order of preference
    # List of models to try in order of preference
    FALLBACK_MODELS = [
        # Latest pro models (highest quality text generation)
        "gemini-2.0-pro-exp-02-05",
        "gemini-2.0-pro-exp",
        "gemini-1.5-pro-latest",
        "gemini-1.5-pro",
        "gemini-1.5-pro-002",
        "gemini-1.5-pro-001",
        
        # Flash models (faster responses, may have better quota)
        "gemini-2.0-flash",
        "gemini-2.0-flash-001",
        "gemini-1.5-flash-latest",
        "gemini-1.5-flash",
        "gemini-1.5-flash-002",
        "gemini-1.5-flash-001",
        "gemini-1.5-flash-001-tuning",
        
        # Lite models (smaller, may have better quota availability)
        "gemini-2.0-flash-lite",
        "gemini-2.0-flash-lite-001",
        "gemini-2.0-flash-lite-preview",
        "gemini-2.0-flash-lite-preview-02-05",
        
        # Experimental models
        "gemini-2.0-flash-exp",
        "gemini-exp-1206",
        "learnlm-1.5-pro-experimental",
        
        # Specialty models as last resort
        "gemini-2.0-flash-thinking-exp",
        "gemini-2.0-flash-thinking-exp-1219",
        "gemini-2.0-flash-thinking-exp-01-21"
    ]
    last_exception = None
    
    # Track which models we've already tried to avoid duplicates
    tried_models = set()
    
    # First try with the loaded model
    try:
        if hasattr(model, 'model_name'):
            model_name = model.model_name
            tried_models.add(model_name)
            # Also add the version without prefix if it has one
            if model_name.startswith("models/"):
                tried_models.add(model_name.split('/')[-1])
            # And add the version with prefix if it doesn't have one
            else:
                tried_models.add(f"models/{model_name}")
        
        return func(model, *args, **kwargs)
    except Exception as e:
        last_exception = e
        # Only continue to fallbacks if it's a quota error
        if "429 Resource has been exhausted" not in str(e) and "quota" not in str(e).lower():
            raise e
        
        model_name = getattr(model, 'model_name', 'unknown')
        print(f"Error with loaded model ({model_name}): {str(e)}")
        print(f"Trying fallback models...")
    
    # Try each fallback model in sequence
    for model_name in FALLBACK_MODELS:
        # Skip if we've already tried this model
        if model_name in tried_models or f"models/{model_name}" in tried_models:
            continue
            
        try:
            print(f"Attempting to use {model_name} model...")
            # Add both versions to tried_models to avoid duplicates
            tried_models.add(model_name)
            tried_models.add(f"models/{model_name}")
            
            fallback_model = genai.GenerativeModel(model_name)
            # Don't modify the original args, just pass the model as the first argument
            return func(fallback_model, *args, **kwargs)
        except Exception as e:
            last_exception = e
            print(f"Error with fallback model {model_name}: {str(e)}")
            # Continue to the next model for quota errors or model not found errors
            if ("429 Resource has been exhausted" not in str(e) and 
                "quota" not in str(e).lower() and 
                "404" not in str(e) and 
                "not found" not in str(e).lower()):
                break
    
    # If we get here, all models failed
    print("All models have failed. Raising the last exception.")
    raise last_exception


def read_file(file_path: str) -> str:
    """Read and return the content of a file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            return file.read()
    except Exception as e:
        print(f"Error reading file {file_path}: {str(e)}")
        sys.exit(1)


def identify_latex_sections(content: str) -> Dict[str, Tuple[int, int]]:
    """
    Identify the main sections in the LaTeX resume and their positions.
    Returns a dictionary mapping section names to (start, end) positions.
    """
    # Common section commands in LaTeX resumes
    section_patterns = [
        r'\\section{([^}]+)}',
        r'\\subsection{([^}]+)}',
        r'\\begin{(\w+)}',  # For environment-based sections
    ]
    
    sections = {}
    last_section = None
    last_pos = 0
    
    for pattern in section_patterns:
        for match in re.finditer(pattern, content):
            section_name = match.group(1)
            start_pos = match.start()
            
            if last_section and start_pos > last_pos:
                sections[last_section] = (last_pos, start_pos)
            
            last_section = section_name
            last_pos = start_pos
    
    # Add the last section to end of document
    if last_section:
        sections[last_section] = (last_pos, len(content))
    
    return sections


def generate_tailored_content(model: Any, resume_content: str, jd_content: str, 
                            company: str, position: str) -> str:
    """
    Use Gemini AI to tailor the resume content based on the job description.
    
    Args:
        model: The Gemini AI model to use
        resume_content: The original LaTeX resume content
        jd_content: The job description text
        company: The company name
        position: The position being applied for
        
    Returns:
        str: The tailored resume content, or the original content if tailoring fails
    """
    # Define the actual content generation function to be used with retry_with_models
    def _generate_content(model: Any, resume_content: str, jd_content: str, 
                        company: str, position: str) -> str:
        try:
            print("Sending request to Gemini AI... (this may take a minute)")
            start_time = time.time()

            # Create the prompt using the function parameters
            content_prompt = f"""
            You are an expert ATS-optimized resume tailoring specialist who helps job seekers optimize their resumes to match specific job descriptions. I need you to tailor a LaTeX resume for a {position} position at {company}.

            ## STEP 1: ANALYZE THE JOB DESCRIPTION
            First, carefully analyze the job description below and extract:
            1. Essential hard skills and technical requirements (at least 5-8)
            2. Essential soft skills (at least 3-5)
            3. Key responsibilities of the role
            4. Industry-specific terminology and buzzwords
            5. Required years of experience or qualifications
            6. Company values or culture indicators

            Job Description:
            ```
            {jd_content}
            ```

            ## STEP 2: ANALYZE THE RESUME
            Now, analyze the current LaTeX resume and identify:
            1. Which required skills from the job description are already present
            2. Which relevant experiences could be reframed to better match the job requirements
            3. Which achievements could be quantified or enhanced to demonstrate required competencies

            Current Resume:
            ```
            {resume_content}
            ```

            ## STEP 3: APPLY STRATEGIC TAILORING
            Now, tailor the resume using these specific strategies:

            1. SUMMARY/OBJECTIVE SECTION:
            - Include the exact job title ({position})
            - Incorporate 3-4 of the most important skills from the job description
            - Mirror the language used in the company's job description
            - Briefly highlight relevant experience that matches the job requirements

            2. SKILLS SECTION:
            - Prioritize skills mentioned in the job description
            - Use exact keywords/phrases from the job description
            - Organize skills to highlight those most relevant to the position first
            - Add any missing relevant skills from the job description that you genuinely possess

            3. WORK EXPERIENCE SECTION:
            - Rewrite bullet points to incorporate key requirements and terminology from the job description
            - Begin each bullet with strong action verbs aligned with the job requirements
            - Quantify achievements with specific metrics, percentages, and outcomes where possible
            - Focus on accomplishments that demonstrate the skills needed for the {position} role
            - Emphasize projects/tasks that align with the primary responsibilities in the job description

            4. EDUCATION & CERTIFICATIONS:
            - Emphasize education/certifications that align with the job requirements
            - Include relevant coursework or projects if they align with the job requirements

            ## CRITICAL REQUIREMENTS:
            - Maintain the EXACT same LaTeX structure and formatting
            - Preserve all LaTeX commands and environments
            - Ensure special LaTeX characters (%, $, #, &, etc.) are properly escaped
            - Do not add or remove any LaTeX environments or major structural elements
            - Ensure each bullet point includes at least one keyword from the job description
            - Match terminology exactly (e.g., if they say "project management", use "project management" not "managing projects")
            - Make tailoring subtle and natural - it should not appear obviously modified for one specific job

            Return ONLY the modified LaTeX code with no explanations or comments outside the LaTeX document.
            """

            response = model.generate_content(content_prompt)

            elapsed_time = time.time() - start_time
            print(f"Received response from Gemini AI in {elapsed_time:.2f} seconds.")

            # Extract the tailored content from the response
            tailored_content = response.text

            # Clean up the response if it includes markdown code blocks
            # Clean up the response if it includes markdown code blocks
            if "```" in tailored_content:
                # Extract content between the first and last code block markers
                match = re.search(r"```(?:latex)?\s*([\s\S]*?)```", tailored_content)
                if match:
                    tailored_content = match.group(1).strip()
                else:
                    # If regex matching fails, manually remove code block markers
                    tailored_content = tailored_content.replace("```latex", "").replace("```", "").strip()
            return tailored_content
        except Exception as e:
            if "429 Resource has been exhausted" in str(e) or "quota" in str(e).lower():
                # Let this be caught by the retry mechanism
                raise e
            else:
                print(f"Error generating tailored content: {str(e)}")
                return resume_content
    
    try:
        return retry_with_models(_generate_content, model, resume_content, jd_content, company, position)
    except Exception as e:
        print(f"Error generating tailored content after trying all models: {str(e)}")
        print("Returning original content as fallback.")
        return resume_content

def extract_company_and_position(model: Any, jd_content: str) -> Tuple[str, str]:
    """
    Extract company name and position from job description using Gemini AI.
    
    Args:
        model: The Gemini AI model
        jd_content: The job description text
        
    Returns:
        A tuple containing (company_name, position_name)
        Returns ("Unknown Company", "Unknown Position") if extraction fails
    """
    prompt = f"""
    Please extract the company name and position title from the following job description.
    Return ONLY a JSON object with two fields: "company" and "position".
    Do not include any explanation, just the JSON object.
    
    Job Description:
    ```
    {jd_content}
    ```
    
    Example response format:
    {{
        "company": "Example Corp",
        "position": "Senior Software Engineer"
    }}
    """
    
    def _extract_info(model: Any, prompt_text: str) -> Tuple[str, str]:
        try:
            print("Extracting company and position from job description...")
            response = model.generate_content(prompt_text)
            
            # Check if response is None or empty
            if response is None or not hasattr(response, 'text') or not response.text:
                print("Warning: Empty or invalid response from Gemini API")
                return "Unknown Company", "Unknown Position"
                
            result_text = response.text.strip()
            
            # Print the raw response for diagnostic purposes
            print("\nDiagnostic - Raw response from Gemini:")
            print(f"---\n{result_text}\n---")
            
            # Parsing approach 1: Extract JSON from code blocks
            extracted_info = None
            
            # Method 1: Try to extract JSON from code blocks
            if "```" in result_text:
                try:
                    match = re.search(r"```(?:json)?(.+?)```", result_text, re.DOTALL)
                    if match:
                        json_text = match.group(1).strip()
                        print(f"Extracted JSON from code blocks: {json_text}")
                        extracted_info = json.loads(json_text)
                except (json.JSONDecodeError, AttributeError) as e:
                    print(f"Failed to parse JSON from code blocks: {str(e)}")
            
            # Method 2: If method 1 failed, try to find JSON-like structure with regex
            if not extracted_info:
                try:
                    # Look for JSON-like pattern with braces
                    json_pattern = r"\{[^{}]*\"company\"[^{}]*\"position\"[^{}]*\}"
                    match = re.search(json_pattern, result_text, re.DOTALL)
                    if match:
                        json_text = match.group(0).strip()
                        print(f"Extracted JSON using regex pattern: {json_text}")
                        extracted_info = json.loads(json_text)
                except (json.JSONDecodeError, AttributeError) as e:
                    print(f"Failed to parse JSON using regex pattern: {str(e)}")
            
            # Method 3: Try parsing the whole response as JSON after cleaning
            if not extracted_info:
                try:
                    # Clean the text - remove backticks, extra spaces, etc.
                    cleaned_text = result_text.replace("```", "").replace("json", "").strip()
                    print(f"Attempting to parse cleaned text as JSON: {cleaned_text}")
                    extracted_info = json.loads(cleaned_text)
                except json.JSONDecodeError as e:
                    print(f"Failed to parse cleaned text as JSON: {str(e)}")
            
            # If we successfully parsed the JSON, extract the company and position
            if extracted_info:
                company = extracted_info.get("company", "Unknown Company")
                position = extracted_info.get("position", "Unknown Position")
                
                print(f"Extracted Company: {company}")
                print(f"Extracted Position: {position}")
                
                return company, position
            
            # Fallback: Try to extract company and position directly with regex
            print("Falling back to regex extraction...")
            
            # Initialize default values
            company = "Unknown Company"
            position = "Unknown Position"
            
            # Try to find company name with common patterns
            company_match = re.search(r"company\"?\s*:\s*\"([^\"]+)\"", result_text, re.IGNORECASE)
            if company_match:
                company = company_match.group(1)
            
            # Try to find position with common patterns
            position_match = re.search(r"position\"?\s*:\s*\"([^\"]+)\"", result_text, re.IGNORECASE)
            if position_match:
                position = position_match.group(1)
            
            print(f"Extracted via regex - Company: {company}, Position: {position}")
            return company, position
            
        except Exception as e:
            if "429 Resource has been exhausted" in str(e) or "quota" in str(e).lower():
                # Let this be caught by the retry mechanism
                raise e
            else:
                print(f"Error extracting from response: {str(e)}")
                return "Unknown Company", "Unknown Position"
    
    try:
        return retry_with_models(_extract_info, model, prompt)
    except Exception as e:
        print(f"Error extracting company and position: {str(e)}")
        print(f"Exception type: {type(e).__name__}")
        
        # Print stack trace for better diagnostics
        import traceback
        # Print stack trace for better diagnostics
        import traceback
        print("Stack trace:")
        traceback.print_exc()

        return "Unknown Company", "Unknown Position"
def save_tailored_resume(content: str, output_path: str) -> None:
    """Save the tailored resume content to the specified file."""
    try:
        with open(output_path, 'w', encoding='utf-8') as file:
            file.write(content)
        print(f"Tailored resume successfully saved to: {output_path}")
    except Exception as e:
        print(f"Error saving tailored resume: {str(e)}")
        sys.exit(1)


def main() -> None:
    """Main function to orchestrate the resume tailoring process."""
    args = parse_arguments()
    
    # Get API key from environment variable
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("Error: GEMINI_API_KEY environment variable is not set.")
        print("Please set the GEMINI_API_KEY environment variable with your Gemini API key.")
        sys.exit(1)
    
    # Set up Gemini API
    setup_gemini_api(api_key)
    
    # List available models and select the best one to use
    selected_model = list_available_models()

    # Load the model
    try:
        model = genai.GenerativeModel(selected_model)
        print(f"Gemini model '{selected_model}' loaded successfully.")
    except Exception as e:
        print(f"Error loading Gemini model: {str(e)}")
        sys.exit(1)
    
    # Read input files
    resume_content = read_file(args.template)
    jd_content = read_file(args.jd)
    
    # Extract company and position from job description if not provided
    company = args.company
    position = args.position
    
    # Use provided company/position or try to extract them
    extraction_success = True
    if company is None or position is None:
        try:
            print("Attempting to extract company and position from job description...")
            extracted_company, extracted_position = extract_company_and_position(model, jd_content)
            
            # Use extracted values only when not provided via command line
            if company is None:
                company = extracted_company
            if position is None:
                position = extracted_position
                
            # Check if extraction was meaningful
            if company == "Unknown Company" and position == "Unknown Position":
                print("Warning: Failed to extract meaningful company and position information")
                extraction_success = False
        except Exception as e:
            print(f"Error during extraction: {str(e)}")
            extraction_success = False
            
    # Ensure we have defaults even if extraction completely failed
    if company is None:
        company = "Unknown Company"
        print(f"Using default company name: {company}")
    if position is None:
        position = "Unknown Position"
        print(f"Using default position name: {position}")
    
    print(f"Processing resume for {position} at {company}")
    
    # Generate tailored resume using Gemini AI
    try:
        print(f"Generating tailored content for {position} at {company}...")
        tailored_content = generate_tailored_content(
            model, resume_content, jd_content, company, position
        )
        if not tailored_content or tailored_content == resume_content:
            print("Warning: Generated content is empty or unchanged. Using original resume as fallback.")
            tailored_content = resume_content
    except Exception as e:
        print(f"Error generating tailored content: {str(e)}")
        print("Using original resume as fallback.")
        tailored_content = resume_content
    # Add a comment header for reference
    header_comment = f"% Tailored resume for {company} - {position}\n"
    header_comment += f"% Auto-tailored using Gemini AI on {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
    
    # Save the tailored resume
    save_tailored_resume(header_comment + tailored_content, args.output)
    
    print("Resume tailoring completed successfully.")


if __name__ == "__main__":
    main()

