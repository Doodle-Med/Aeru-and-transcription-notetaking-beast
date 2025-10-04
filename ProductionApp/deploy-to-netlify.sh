#!/bin/bash

# Deploy Privacy Policy to Netlify
# This script helps you deploy your privacy policy to Netlify

set -e

echo "🚀 Deploying Whisper Control Mobile Privacy Policy to Netlify..."

# Check if Netlify CLI is installed
if ! command -v netlify &> /dev/null; then
    echo "❌ Netlify CLI not found. Installing..."
    npm install -g netlify-cli
fi

# Check if we're in the right directory
if [ ! -f "privacy-policy.html" ]; then
    echo "❌ privacy-policy.html not found in current directory"
    echo "Please run this script from the ProductionApp directory"
    exit 1
fi

# Login to Netlify (if not already logged in)
echo "🔐 Checking Netlify authentication..."
if ! netlify status &> /dev/null; then
    echo "Please log in to Netlify..."
    netlify login
fi

# Deploy to Netlify
echo "📦 Deploying to Netlify..."
netlify deploy --prod --dir .

echo "✅ Privacy policy deployed successfully!"
echo "🌐 Your privacy policy is now live at the URL provided above"
echo ""
echo "📋 Next steps:"
echo "1. Copy the deployment URL"
echo "2. Use it as your Privacy Policy URL in App Store Connect"
echo "3. Update your app's privacy policy link"
