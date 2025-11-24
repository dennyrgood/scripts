#!/bin/bash

# Script to verify all old repo names have been updated
# Run from ~/repos directory

echo "🔍 Checking for old repository name references..."
echo "================================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

cd ~/repos

# Counter for issues found
issues=0

echo "1️⃣  Checking for 'MoviesShowsFullEdit' references..."
echo "---------------------------------------------------"
results=$(grep -r "MoviesShowsFullEdit" --exclude-dir=.git --exclude-dir=OLD --exclude="*.pyc" --exclude-dir=__pycache__ . 2>/dev/null)
if [ -n "$results" ]; then
    echo -e "${RED}❌ Found references to 'MoviesShowsFullEdit':${NC}"
    echo "$results"
    ((issues++))
else
    echo -e "${GREEN}✅ No references to 'MoviesShowsFullEdit' found${NC}"
fi
echo ""

echo "2️⃣  Checking for 'USDZ_AVP' references..."
echo "---------------------------------------------------"
results=$(grep -r "USDZ_AVP" --exclude-dir=.git --exclude-dir=OLD --exclude="*.pyc" --exclude-dir=__pycache__ . 2>/dev/null)
if [ -n "$results" ]; then
    echo -e "${RED}❌ Found references to 'USDZ_AVP':${NC}"
    echo "$results"
    ((issues++))
else
    echo -e "${GREEN}✅ No references to 'USDZ_AVP' found${NC}"
fi
echo ""

echo "3️⃣  Checking for 'GooglePhotos' (should be 'google-photos')..."
echo "---------------------------------------------------"
# Exclude legitimate Swift code comments and Python cache
results=$(grep -r "GooglePhotos" --exclude-dir=.git --exclude-dir=OLD --exclude="*.pyc" --exclude-dir=__pycache__ --exclude-dir=google-photos . 2>/dev/null | grep -v "\.swiftcrossimport" | grep -v "old_device")
if [ -n "$results" ]; then
    echo -e "${RED}❌ Found references to 'GooglePhotos':${NC}"
    echo "$results"
    ((issues++))
else
    echo -e "${GREEN}✅ No references to 'GooglePhotos' found${NC}"
fi
echo ""

echo "4️⃣  Checking for 'PlaceObjects' in URLs/paths (Swift code is OK)..."
echo "---------------------------------------------------"
# Only check for PlaceObjects in URLs and file paths, not Swift code
results=$(grep -r "PlaceObjects" --exclude-dir=.git --exclude-dir=OLD --exclude="*.pyc" --exclude-dir=__pycache__ --exclude-dir=place-objects --exclude="*.xcodeproj" --exclude="*.xcuserstate" . 2>/dev/null | grep -E "(github\.com|clone|MyWebsiteGIT)" | grep -v "dennyrgood/place-objects")
if [ -n "$results" ]; then
    echo -e "${RED}❌ Found references to 'PlaceObjects' in URLs/paths:${NC}"
    echo "$results"
    ((issues++))
else
    echo -e "${GREEN}✅ No problematic 'PlaceObjects' references found${NC}"
fi
echo ""

echo "5️⃣  Checking for old path 'MyWebsiteGIT' or 'MywebsiteGIT'..."
echo "---------------------------------------------------"
results=$(grep -r -E "MyWebsiteGIT|MywebsiteGIT" --exclude-dir=.git --exclude-dir=OLD --exclude="*.pyc" --exclude-dir=__pycache__ . 2>/dev/null)
if [ -n "$results" ]; then
    echo -e "${YELLOW}⚠️  Found references to old path 'MyWebsiteGIT':${NC}"
    echo "$results"
    echo -e "${YELLOW}(These should probably be changed to 'repos')${NC}"
    ((issues++))
else
    echo -e "${GREEN}✅ No references to 'MyWebsiteGIT' found${NC}"
fi
echo ""

echo "================================================"
if [ $issues -eq 0 ]; then
    echo -e "${GREEN}🎉 All checks passed! Repository names are standardized.${NC}"
else
    echo -e "${RED}⚠️  Found $issues issue(s) that need attention.${NC}"
fi
echo ""
