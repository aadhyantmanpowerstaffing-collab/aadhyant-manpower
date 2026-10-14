// Canonical endpointless Flow. Keep the review JSON in sync.
export const registrationFlowName = "aadhyant_registration_alerts_v1";
export const registrationFlowPolicy = "wa-registration-alerts-v1";
export const registrationFlow = {
  "version": "3.1",
  "screens": [
    {
      "id": "PERSONAL",
      "title": "Aadhyant Registration",
      "data": {
        "requirement_code": {
          "type": "string",
          "__example__": "AAD-2026-000003"
        }
      },
      "layout": {
        "type": "SingleColumnLayout",
        "children": [
          {
            "type": "TextCaption",
            "text": "${data.requirement_code}"
          },
          {
            "type": "Form",
            "name": "personal",
            "children": [
              {
                "type": "TextInput",
                "name": "full_name",
                "label": "પૂરું નામ",
                "required": true,
                "max-chars": 160
              },
              {
                "type": "TextInput",
                "name": "age",
                "label": "ઉંમર (16 થી 75)",
                "required": true,
                "input-type": "number",
                "max-chars": 2
              },
              {
                "type": "Dropdown",
                "name": "gender",
                "label": "Gender",
                "required": true,
                "data-source": [
                  {
                    "id": "Male",
                    "title": "પુરુષ"
                  },
                  {
                    "id": "Female",
                    "title": "સ્ત્રી"
                  },
                  {
                    "id": "Other / Prefer not to say",
                    "title": "અન્ય / જણાવવું નથી"
                  }
                ]
              },
              {
                "type": "Dropdown",
                "name": "state",
                "label": "રાજ્ય",
                "required": true,
                "data-source": [
                  {
                    "id": "Andaman and Nicobar Islands",
                    "title": "Andaman and Nicobar Islands"
                  },
                  {
                    "id": "Andhra Pradesh",
                    "title": "Andhra Pradesh"
                  },
                  {
                    "id": "Arunachal Pradesh",
                    "title": "Arunachal Pradesh"
                  },
                  {
                    "id": "Assam",
                    "title": "Assam"
                  },
                  {
                    "id": "Bihar",
                    "title": "Bihar"
                  },
                  {
                    "id": "Chandigarh",
                    "title": "Chandigarh"
                  },
                  {
                    "id": "Chhattisgarh",
                    "title": "Chhattisgarh"
                  },
                  {
                    "id": "Dadra and Nagar Haveli and Daman and Diu",
                    "title": "Dadra and Nagar Haveli and Dam"
                  },
                  {
                    "id": "Delhi",
                    "title": "Delhi"
                  },
                  {
                    "id": "Goa",
                    "title": "Goa"
                  },
                  {
                    "id": "Gujarat",
                    "title": "Gujarat"
                  },
                  {
                    "id": "Haryana",
                    "title": "Haryana"
                  },
                  {
                    "id": "Himachal Pradesh",
                    "title": "Himachal Pradesh"
                  },
                  {
                    "id": "Jammu and Kashmir",
                    "title": "Jammu and Kashmir"
                  },
                  {
                    "id": "Jharkhand",
                    "title": "Jharkhand"
                  },
                  {
                    "id": "Karnataka",
                    "title": "Karnataka"
                  },
                  {
                    "id": "Kerala",
                    "title": "Kerala"
                  },
                  {
                    "id": "Ladakh",
                    "title": "Ladakh"
                  },
                  {
                    "id": "Lakshadweep",
                    "title": "Lakshadweep"
                  },
                  {
                    "id": "Madhya Pradesh",
                    "title": "Madhya Pradesh"
                  },
                  {
                    "id": "Maharashtra",
                    "title": "Maharashtra"
                  },
                  {
                    "id": "Manipur",
                    "title": "Manipur"
                  },
                  {
                    "id": "Meghalaya",
                    "title": "Meghalaya"
                  },
                  {
                    "id": "Mizoram",
                    "title": "Mizoram"
                  },
                  {
                    "id": "Nagaland",
                    "title": "Nagaland"
                  },
                  {
                    "id": "Odisha",
                    "title": "Odisha"
                  },
                  {
                    "id": "Puducherry",
                    "title": "Puducherry"
                  },
                  {
                    "id": "Punjab",
                    "title": "Punjab"
                  },
                  {
                    "id": "Rajasthan",
                    "title": "Rajasthan"
                  },
                  {
                    "id": "Sikkim",
                    "title": "Sikkim"
                  },
                  {
                    "id": "Tamil Nadu",
                    "title": "Tamil Nadu"
                  },
                  {
                    "id": "Telangana",
                    "title": "Telangana"
                  },
                  {
                    "id": "Tripura",
                    "title": "Tripura"
                  },
                  {
                    "id": "Uttar Pradesh",
                    "title": "Uttar Pradesh"
                  },
                  {
                    "id": "Uttarakhand",
                    "title": "Uttarakhand"
                  },
                  {
                    "id": "West Bengal",
                    "title": "West Bengal"
                  }
                ]
              },
              {
                "type": "TextInput",
                "name": "district",
                "label": "જિલ્લો",
                "required": true,
                "max-chars": 160
              },
              {
                "type": "TextInput",
                "name": "current_village_city",
                "label": "ગામ / શહેર",
                "required": true,
                "max-chars": 200
              },
              {
                "type": "Footer",
                "label": "આગળ",
                "on-click-action": {
                  "name": "navigate",
                  "next": {
                    "type": "screen",
                    "name": "EDUCATION"
                  },
                  "payload": {
                    "full_name": "${form.full_name}",
                    "age": "${form.age}",
                    "gender": "${form.gender}",
                    "state": "${form.state}",
                    "district": "${form.district}",
                    "current_village_city": "${form.current_village_city}",
                    "requirement_code": "${data.requirement_code}"
                  }
                }
              }
            ]
          }
        ]
      }
    },
    {
      "id": "EDUCATION",
      "title": "Job અને સંમતિ",
      "terminal": true,
      "success": true,
      "data": {
        "full_name": {
          "type": "string",
          "__example__": "Example"
        },
        "age": {
          "type": "string",
          "__example__": "Example"
        },
        "gender": {
          "type": "string",
          "__example__": "Example"
        },
        "state": {
          "type": "string",
          "__example__": "Example"
        },
        "district": {
          "type": "string",
          "__example__": "Example"
        },
        "current_village_city": {
          "type": "string",
          "__example__": "Example"
        },
        "requirement_code": {
          "type": "string",
          "__example__": "AAD-2026-000003"
        }
      },
      "layout": {
        "type": "SingleColumnLayout",
        "children": [
          {
            "type": "TextCaption",
            "text": "${data.requirement_code}"
          },
          {
            "type": "Form",
            "name": "education",
            "children": [
              {
                "type": "Dropdown",
                "name": "highest_qualification",
                "label": "Qualification",
                "required": true,
                "data-source": [
                  {
                    "id": "Below 10th",
                    "title": "Below 10th"
                  },
                  {
                    "id": "10th",
                    "title": "10th"
                  },
                  {
                    "id": "12th",
                    "title": "12th"
                  },
                  {
                    "id": "ITI",
                    "title": "ITI"
                  },
                  {
                    "id": "Diploma",
                    "title": "Diploma"
                  },
                  {
                    "id": "Graduate",
                    "title": "Graduate"
                  },
                  {
                    "id": "Post Graduate",
                    "title": "Post Graduate"
                  },
                  {
                    "id": "Other",
                    "title": "Other"
                  }
                ]
              },
              {
                "type": "TextInput",
                "name": "course_trade_specialization",
                "label": "Trade / Course",
                "required": true,
                "max-chars": 160,
                "helper-text": "ન હોય તો NA લખો"
              },
              {
                "type": "Dropdown",
                "name": "experience_status",
                "label": "અનુભવ",
                "required": true,
                "data-source": [
                  {
                    "id": "Fresher",
                    "title": "Fresher"
                  },
                  {
                    "id": "Experienced",
                    "title": "Experienced"
                  }
                ]
              },
              {
                "type": "Dropdown",
                "name": "interview_available",
                "label": "Interview ઉપલબ્ધ?",
                "required": true,
                "data-source": [
                  {
                    "id": "Yes",
                    "title": "હા"
                  },
                  {
                    "id": "No",
                    "title": "ના"
                  }
                ]
              },
              {
                "type": "TextBody",
                "text": "Submit કરવાથી આ job માટે તમારો રસ અને basic candidate registration નોંધાશે. Aadhaar, bank details અને password અહીં આપવાના નથી."
              },
              {
                "type": "OptIn",
                "name": "registration_consent",
                "label": "હું registration અને આ job માટે સંપર્કની સંમતિ આપું છું.",
                "required": true
              },
              {
                "type": "TextBody",
                "text": "Job alerts વૈકલ્પિક છે. પસંદ કરશો તો Aadhyantની બધી job alerts આ WhatsApp નંબર પર મળશે, job તમને લાગુ પડે કે ન પડે. બંધ કરવા STOP મોકલી શકો છો."
              },
              {
                "type": "OptIn",
                "name": "job_alert_consent",
                "label": "મને Aadhyantની બધી job alerts WhatsApp પર મોકલો.",
                "required": false,
                "init-value": false
              },
              {
                "type": "Footer",
                "label": "Submit",
                "on-click-action": {
                  "name": "complete",
                  "payload": {
                    "full_name": "${data.full_name}",
                    "age": "${data.age}",
                    "gender": "${data.gender}",
                    "state": "${data.state}",
                    "district": "${data.district}",
                    "current_village_city": "${data.current_village_city}",
                    "highest_qualification": "${form.highest_qualification}",
                    "course_trade_specialization": "${form.course_trade_specialization}",
                    "experience_status": "${form.experience_status}",
                    "interview_available": "${form.interview_available}",
                    "registration_consent": "${form.registration_consent}",
                    "job_alert_consent": "${form.job_alert_consent}",
                    "form_kind": "aadhyant_registration_v1",
                    "consent_policy_version": "wa-registration-alerts-v1"
                  }
                }
              }
            ]
          }
        ]
      }
    }
  ]
};
