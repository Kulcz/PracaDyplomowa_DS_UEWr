from google_scholar_py import CustomGoogleScholarProfiles
import json

parser = CustomGoogleScholarProfiles()
data = parser.scrape_google_scholar_profiles(
    query='Wrocław University of Environmental and Life Sciences',
    pagination=False,
    save_to_csv=True,
    save_to_json=False
)
print(json.dumps(data, indent=2))