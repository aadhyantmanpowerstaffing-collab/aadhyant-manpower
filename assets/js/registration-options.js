(function () {
  'use strict';

  const sets = Object.freeze({
    states: Object.freeze([
      'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chandigarh',
      'Chhattisgarh', 'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat', 'Haryana',
      'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand', 'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep',
      'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Puducherry',
      'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
      'West Bengal'
    ]),
    genders: Object.freeze(['Male', 'Female', 'Other / Prefer not to say']),
    qualifications: Object.freeze(['Below 10th', '10th', '12th', 'ITI', 'Diploma', 'Graduate', 'Post Graduate', 'Other']),
    candidateTypes: Object.freeze(['Fresher', 'Experienced']),
    interviewAvailability: Object.freeze(['Yes', 'No']),
    experienceDurations: Object.freeze(['Less than 1 year', '1 year', '2 years', '3 years', '4 years', '5 years', '6-10 years', '10+ years', 'Other']),
    workforceSizes: Object.freeze(['1-10', '11-50', '51-200', '201-500', '501-1000', '1000+']),
    industries: Object.freeze([
      'Automotive', 'Engineering', 'FMCG', 'Manufacturing', 'Warehouse & Logistics', 'Industrial Operations',
      'Construction & Infrastructure', 'Healthcare', 'Hospitality', 'Retail & E-commerce',
      'IT & Business Services', 'Other'
    ]),
    vacancyExperience: Object.freeze(['Both', 'Fresher', 'Experienced']),
    vacancyGender: Object.freeze(['Any', 'Male', 'Female']),
    vacancyShifts: Object.freeze(['General', 'Day', 'Night', 'Rotational', 'Other']),
    vacancyFacilities: Object.freeze(['Not Applicable', 'Yes', 'No'])
  });

  // District data: Government of India, Ministry of Panchayati Raj, Local Government Directory
  // (LGD) stateList/districtList web services. Snapshot retrieved 2026-08-31: 784 districts across
  // every one of the 36 configured States/UTs. Source:
  // https://lgdirectory.gov.in/webservices/lgdws/stateList
  // Labels intentionally match the existing text-based profile contracts; LGD state-name casing is
  // normalized only where it differs from the application's established State/UT labels.
  const districtsByState = Object.freeze({
    'Andaman and Nicobar Islands': Object.freeze(["Nicobars","North And Middle Andaman","South Andamans"]),
    'Andhra Pradesh': Object.freeze(["Alluri Sitharama Raju","Anakapalli","Ananthapuramu","Annamayya","Bapatla","Chittoor","Dr. B.R. Ambedkar Konaseema","East Godavari","Eluru","Guntur","Kakinada","Krishna","Kurnool","Markapuram","Nandyal","Ntr","Palnadu","Parvathipuram Manyam","Polavaram","Prakasam","Sri Potti Sriramulu Nellore","Sri Sathya Sai","Srikakulam","Tirupati","Visakhapatnam","Vizianagaram","West Godavari","Y.S.R. Kadapa"]),
    'Arunachal Pradesh': Object.freeze(["Anjaw","Bichom","Changlang","Dibang Valley","East Kameng","East Siang","Kamle","Keyi Panyor","Kra Daadi","Kurung Kumey","Leparada","Lohit","Longding","Lower Dibang Valley","Lower Siang","Lower Subansiri","Namsai","Pakke Kessang","Papum Pare","Shi Yomi","Siang","Tawang","Tirap","Upper Siang","Upper Subansiri","West Kameng","West Siang"]),
    'Assam': Object.freeze(["Bajali","Baksa","Barpeta","Biswanath","Bongaigaon","Cachar","Charaideo","Chirang","Darrang","Dhemaji","Dhubri","Dibrugarh","Dima Hasao","Goalpara","Golaghat","Hailakandi","Hojai","Jorhat","Kamrup","Kamrup Metro","Karbi Anglong","Kokrajhar","Lakhimpur","Majuli","Marigaon","Nagaon","Nalbari","Sivasagar","Sonitpur","South Salmara Mancachar","Sribhumi","Tamulpur","Tinsukia","Udalguri","West Karbi Anglong"]),
    'Bihar': Object.freeze(["Araria","Arwal","Aurangabad","Banka","Begusarai","Bhagalpur","Bhojpur","Buxar","Darbhanga","Gaya","Gopalganj","Jamui","Jehanabad","Kaimur (Bhabua)","Katihar","Khagaria","Kishanganj","Lakhisarai","Madhepura","Madhubani","Munger","Muzaffarpur","Nalanda","Nawada","Pashchim Champaran","Patna","Purbi Champaran","Purnia","Rohtas","Saharsa","Samastipur","Saran","Sheikhpura","Sheohar","Sitamarhi","Siwan","Supaul","Vaishali"]),
    'Chandigarh': Object.freeze(["Chandigarh"]),
    'Chhattisgarh': Object.freeze(["Balod","Balodabazar-Bhatapara","Balrampur-Ramanujganj","Bastar","Bemetara","Bijapur","Bilaspur","Dakshin Bastar Dantewada","Dhamtari","Durg","Gariyaband","Gaurela-Pendra-Marwahi","Janjgir-Champa","Jashpur","Kabeerdham","Khairagarh-Chhuikhadan-Gandai","Kondagaon","Korba","Korea","Mahasamund","Manendragarh-Chirmiri-Bharatpur(M C B)","Mohla-Manpur-Ambagarh Chouki","Mungeli","Narayanpur","Raigarh","Raipur","Rajnandgaon","Sakti","Sarangarh-Bilaigarh","Sukma","Surajpur","Surguja","Uttar Bastar Kanker"]),
    'Dadra and Nagar Haveli and Daman and Diu': Object.freeze(["Dadra And Nagar Haveli","Daman","Diu"]),
    'Delhi': Object.freeze(["Central","Central North","East","New Delhi","North","North East","North West","Old Delhi","Outer North","South","South East","South West","West"]),
    'Goa': Object.freeze(["Kushavati","North Goa","South Goa"]),
    'Gujarat': Object.freeze(["Ahmedabad","Amreli","Anand","Arvalli","Banas Kantha","Bharuch","Bhavnagar","Botad","Chhotaudepur","Dahod","Dangs","Devbhumi Dwarka","Gandhinagar","Gir Somnath","Jamnagar","Junagadh","Kachchh","Kheda","Mahesana","Mahisagar","Morbi","Narmada","Navsari","Panch Mahals","Patan","Porbandar","Rajkot","Sabar Kantha","Surat","Surendranagar","Tapi","Vadodara","Valsad","Vav-Tharad"]),
    'Haryana': Object.freeze(["Ambala","Bhiwani","Charkhi Dadri","Faridabad","Fatehabad","Gurugram","Hansi","Hisar","Jhajjar","Jind","Kaithal","Karnal","Kurukshetra","Mahendragarh","Nuh","Palwal","Panchkula","Panipat","Rewari","Rohtak","Sirsa","Sonipat","Yamunanagar"]),
    'Himachal Pradesh': Object.freeze(["Bilaspur","Chamba","Hamirpur","Kangra","Kinnaur","Kullu","Lahaul And Spiti","Mandi","Shimla","Sirmaur","Solan","Una"]),
    'Jammu and Kashmir': Object.freeze(["Anantnag","Bandipora","Baramulla","Budgam","Doda","Ganderbal","Jammu","Kathua","Kishtwar","Kulgam","Kupwara","Poonch","Pulwama","Rajouri","Ramban","Reasi","Samba","Shopian","Srinagar","Udhampur"]),
    'Jharkhand': Object.freeze(["Bokaro","Chatra","Deoghar","Dhanbad","Dumka","East Singhbum","Garhwa","Giridih","Godda","Gumla","Hazaribagh","Jamtara","Khunti","Koderma","Latehar","Lohardaga","Pakur","Palamu","Ramgarh","Ranchi","Sahebganj","Saraikela Kharsawan","Simdega","West Singhbhum"]),
    'Karnataka': Object.freeze(["Bagalkote","Ballari","Belagavi","Bengaluru Rural","Bengaluru South","Bengaluru Urban","Bidar","Chamarajanagar","Chikkaballapura","Chikkamagaluru","Chitradurga","Dakshina Kannada","Davanagere","Dharwad","Gadag","Hassan","Haveri","Kalaburagi","Kodagu","Kolar","Koppal","Mandya","Mysuru","Raichur","Shivamogga","Tumakuru","Udupi","Uttara Kannada","Vijayanagara","Vijayapura","Yadgir"]),
    'Kerala': Object.freeze(["Alappuzha","Ernakulam","Idukki","Kannur","Kasaragod","Kollam","Kottayam","Kozhikode","Malappuram","Palakkad","Pathanamthitta","Thiruvananthapuram","Thrissur","Wayanad"]),
    'Ladakh': Object.freeze(["Kargil","Leh Ladakh"]),
    'Lakshadweep': Object.freeze(["Lakshadweep District"]),
    'Madhya Pradesh': Object.freeze(["Agar-Malwa","Alirajpur","Anuppur","Ashoknagar","Balaghat","Barwani","Betul","Bhind","Bhopal","Burhanpur","Chhatarpur","Chhindwara","Damoh","Datia","Dewas","Dhar","Dindori","Guna","Gwalior","Harda","Indore","Jabalpur","Jhabua","Katni","Khandwa (East Nimar)","Khargone (West Nimar)","Maihar","Mandla","Mandsaur","MAUGANJ","Morena","Narmadapuram","Narsimhapur","Neemuch","Niwari","Pandhurna","Panna","Raisen","Rajgarh","Ratlam","Rewa","Sagar","Satna","Sehore","Seoni","Shahdol","Shajapur","Sheopur","Shivpuri","Sidhi","Singrauli","Tikamgarh","Ujjain","Umaria","Vidisha"]),
    'Maharashtra': Object.freeze(["Ahilyanagar","Akola","Amravati","Beed","Bhandara","Buldhana","Chandrapur","Chhatrapati Sambhajinagar","Dharashiv","Dhule","Gadchiroli","Gondia","Hingoli","Jalgaon","Jalna","Kolhapur","Latur","Mumbai","Mumbai Suburban","Nagpur","Nanded","Nandurbar","Nashik","Palghar","Parbhani","Pune","Raigad","Ratnagiri","Sangli","Satara","Sindhudurg","Solapur","Thane","Wardha","Washim","Yavatmal"]),
    'Manipur': Object.freeze(["Bishnupur","Chandel","Churachandpur","Imphal East","Imphal West","Jiribam","Kakching","Kamjong","Kangpokpi","Noney","Pherzawl","Senapati","Tamenglong","Tengnoupal","Thoubal","Ukhrul"]),
    'Meghalaya': Object.freeze(["East Garo Hills","East Jaintia Hills","East Khasi Hills","Eastern West Khasi Hills","North Garo Hills","Ri Bhoi","South Garo Hills","South West Garo Hills","South West Khasi Hills","West Garo Hills","West Jaintia Hills","West Khasi Hills"]),
    'Mizoram': Object.freeze(["Aizawl","Champhai","Hnahthial","Khawzawl","Kolasib","Lawngtlai","Lunglei","Mamit","Saitual","Serchhip","Siaha"]),
    'Nagaland': Object.freeze(["Chumoukedima","Dimapur","Kiphire","Kohima","Longleng","Meluri","Mokokchung","Mon","Niuland","Noklak","Peren","Phek","Shamator","Tseminyu","Tuensang","Wokha","Zunheboto"]),
    'Odisha': Object.freeze(["Anugola","Balangir","Baleshwar","Baragada","Bhadrak","Boudh","Debagada","Dhenkanal","Gajapati","Ganjam","Jagatsinghapur","Jajpur","Jharsuguda","Kalahandi","Kandhamala","Kataka","Kendrapada","Kendujhar","Khordha","Koraput","Malkangiri","Mayurbhanj","Nabarangpur","Nayagada","Nuapada","Puri","Rayagada","Sambalpur","Subarnapur","Sundaragada"]),
    'Puducherry': Object.freeze(["Karaikal","Puducherry"]),
    'Punjab': Object.freeze(["Amritsar","Barnala","Bathinda","Faridkot","Fatehgarh Sahib","Fazilka","Ferozepur","Gurdaspur","Hoshiarpur","Jalandhar","Kapurthala","Ludhiana","Malerkotla","Mansa","Moga","Pathankot","Patiala","Rupnagar","S.A.S Nagar","Sangrur","Shahid Bhagat Singh Nagar","Sri Muktsar Sahib","Tarn Taran"]),
    'Rajasthan': Object.freeze(["Ajmer","Alwar","Balotra","Banswara","Baran","Barmer","Beawar","Bharatpur","Bhilwara","Bikaner","Bundi","Chittorgarh","Churu","Dausa","Deeg","Dholpur","Didwana-Kuchaman","Dungarpur","Ganganagar","Hanumangarh","Jaipur","Jaisalmer","Jalore","Jhalawar","Jhunjhunu","Jodhpur","Karauli","Khairthal-Tijara","Kota","Kotputli-Behror","Nagaur","Pali","Phalodi","Pratapgarh","Rajsamand","Salumbar","Sawai Madhopur","Sikar","Sirohi","Tonk","Udaipur"]),
    'Sikkim': Object.freeze(["Gangtok","Gyalshing","Mangan","Namchi","Pakyong","Soreng"]),
    'Tamil Nadu': Object.freeze(["Ariyalur","Chengalpattu","Chennai","Coimbatore","Cuddalore","Dharmapuri","Dindigul","Erode","Kallakurichi","Kancheepuram","Kanniyakumari","Karur","Krishnagiri","Madurai","Mayiladuthurai","Nagapattinam","Namakkal","Perambalur","Pudukkottai","Ramanathapuram","Ranipet","Salem","Sivaganga","Tenkasi","Thanjavur","The Nilgiris","Theni","Thiruvallur","Thiruvarur","Thoothukkudi","Tiruchirappalli","Tirunelveli","Tirupathur","Tiruppur","Tiruvannamalai","Vellore","Viluppuram","Virudhunagar"]),
    'Telangana': Object.freeze(["Adilabad","Bhadradri Kothagudem","Hanumakonda","Hyderabad","Jagitial","Jangoan","Jayashankar Bhupalapally","Jogulamba Gadwal","Kamareddy","Karimnagar","Khammam","Kumuram Bheem Asifabad","Mahabubabad","Mahabubnagar","Mancherial","Medak","Medchal Malkajgiri","Mulugu","Nagarkurnool","Nalgonda","Narayanpet","Nirmal","Nizamabad","Peddapalli","Rajanna Sircilla","Ranga Reddy","Sangareddy","Siddipet","Suryapet","Vikarabad","Wanaparthy","Warangal","Yadadri Bhuvanagiri"]),
    'Tripura': Object.freeze(["Dhalai","Gomati","Khowai","North Tripura","Sepahijala","South Tripura","Unakoti","West Tripura"]),
    'Uttar Pradesh': Object.freeze(["Agra","Aligarh","Ambedkar Nagar","Amethi","Amroha","Auraiya","Ayodhya","Azamgarh","Baghpat","Bahraich","Ballia","Balrampur","Banda","Bara Banki","Bareilly","Basti","Bhadohi","Bijnor","Budaun","Bulandshahr","Chandauli","Chitrakoot","Deoria","Etah","Etawah","Farrukhabad","Fatehpur","Firozabad","Gautam Buddha Nagar","Ghaziabad","Ghazipur","Gonda","Gorakhpur","Hamirpur","Hapur","Hardoi","Hathras","Jalaun","Jaunpur","Jhansi","Kannauj","Kanpur Dehat","Kanpur Nagar","Kasganj","Kaushambi","Kheri","Kushinagar","Lalitpur","Lucknow","Mahoba","Mahrajganj","Mainpuri","Mathura","Mau","Meerut","Mirzapur","Moradabad","Muzaffarnagar","Pilibhit","Pratapgarh","Prayagraj","Rae Bareli","Rampur","Saharanpur","Sambhal","Sant Kabir Nagar","Shahjahanpur","Shamli","Shrawasti","Siddharthnagar","Sitapur","Sonbhadra","Sultanpur","Unnao","Varanasi"]),
    'Uttarakhand': Object.freeze(["Almora","Bageshwar","Chamoli","Champawat","Dehradun","Haridwar","Nainital","Pauri Garhwal","Pithoragarh","Rudraprayag","Tehri Garhwal","Udham Singh Nagar","Uttarkashi"]),
    'West Bengal': Object.freeze(["Alipurduar","Bankura","Birbhum","Cooch Behar","Dakshin Dinajpur","Darjeeling","Hooghly","Howrah","Jalpaiguri","Jhargram","Kalimpong","Kolkata","Malda","Murshidabad","Nadia","North 24 Parganas","Paschim Bardhaman","Paschim Medinipur","Purba Bardhaman","Purba Medinipur","Purulia","South 24 Parganas","Uttar Dinajpur"])
  });

  const tradesByQualification = Object.freeze({
    ITI: Object.freeze(['Fitter', 'Electrician', 'Welder', 'Machinist', 'Turner', 'Mechanic Diesel', 'COPA', 'Electronics Mechanic', 'Wireman', 'Other']),
    Diploma: Object.freeze(['Mechanical', 'Electrical', 'Electronics', 'Civil', 'Automobile', 'Production', 'Chemical', 'Other']),
    Graduate: Object.freeze(['Arts', 'Commerce', 'Science', 'Engineering', 'Business Administration', 'Computer Applications', 'Other']),
    'Post Graduate': Object.freeze(['Arts', 'Commerce', 'Science', 'Engineering', 'Business Administration', 'Computer Applications', 'Other']),
    Other: Object.freeze(['Other'])
  });

  function populate(select, values, placeholder) {
    if (!select) return;
    const current = select.value;
    select.replaceChildren();
    if (placeholder !== null) {
      const empty = document.createElement('option');
      empty.value = '';
      empty.textContent = placeholder || select.dataset.placeholder || 'Select an option';
      select.append(empty);
    }
    values.forEach((value) => {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value;
      select.append(option);
    });
    if (current) setValue(select, current);
  }

  function setValue(select, value) {
    if (!select) return;
    const normalized = String(value ?? '').trim();
    if (!normalized) {
      select.value = '';
      return;
    }
    if (![...select.options].some((option) => option.value === normalized)) {
      const option = document.createElement('option');
      option.value = normalized;
      option.textContent = `${normalized} (saved value)`;
      option.dataset.savedValue = 'true';
      select.append(option);
    }
    select.value = normalized;
  }

  function initialize(root = document) {
    root.querySelectorAll('select[data-option-set]').forEach((select) => {
      const values = sets[select.dataset.optionSet];
      if (!values) return;
      populate(select, values, select.dataset.placeholder ?? 'Select an option');
    });
  }

  function setupStateDistrict(form, initial = {}) {
    const state = form?.elements?.state;
    const district = form?.elements?.district;
    if (!state || !district || state.tagName !== 'SELECT' || district.tagName !== 'SELECT') return;

    const savedState = String(initial.state ?? state.value ?? '').trim();
    const savedDistrict = String(initial.district ?? district.value ?? '').trim();
    if (savedState) setValue(state, savedState);

    const sync = (districtToRestore = '') => {
      const selectedState = String(state.value || '').trim();
      const districts = districtsByState[selectedState] || [];
      district.value = '';
      populate(district, districts, selectedState ? 'Select District' : 'Select State first');
      district.disabled = !selectedState;
      district.removeAttribute('data-saved-value');
      if (!districtToRestore || !selectedState) return;
      if (districts.includes(districtToRestore)) {
        district.value = districtToRestore;
      } else if (selectedState === savedState) {
        setValue(district, districtToRestore);
        district.dataset.savedValue = 'true';
      }
    };

    if (state.aadhyantDistrictHandler) state.removeEventListener('change', state.aadhyantDistrictHandler);
    state.aadhyantDistrictHandler = () => sync('');
    state.addEventListener('change', state.aadhyantDistrictHandler);
    sync(savedDistrict);
  }

  function toggleOther(select, wrapper, input) {
    const show = select?.value === 'Other';
    if (wrapper) wrapper.hidden = !show;
    if (input) {
      input.disabled = !show;
      input.required = show;
      if (!show) input.value = '';
    }
  }

  function setupCandidateForm(form, initial = {}) {
    if (!form) return;
    initialize(form);
    const qualification = form.elements.highest_qualification;
    const specialization = form.elements.specialization;
    const specializationOther = form.elements.specialization_other;
    const specializationOtherWrap = form.querySelector('[data-specialization-other]');
    const candidateType = form.elements.candidate_type;
    const experienceWrap = form.querySelector('[data-experience-fields]');
    const duration = form.elements.total_experience;
    const durationOther = form.elements.total_experience_other;
    const durationOtherWrap = form.querySelector('[data-experience-other]');
    const previousRole = form.elements.previous_job_role;

    const syncSpecialization = (saved = '') => {
      const values = tradesByQualification[qualification?.value] || [];
      const hasChoices = values.length > 0;
      if (specialization) {
        populate(specialization, values, hasChoices ? 'Select trade / specialization' : 'Not applicable');
        specialization.disabled = !hasChoices;
      }
      if (!hasChoices) {
        if (specializationOtherWrap) specializationOtherWrap.hidden = true;
        if (specializationOther) {
          specializationOther.disabled = true;
          specializationOther.required = false;
          specializationOther.value = '';
        }
        return;
      }
      if (saved) {
        if (values.includes(saved)) setValue(specialization, saved);
        else {
          setValue(specialization, 'Other');
          specializationOther.value = saved;
        }
      }
      toggleOther(specialization, specializationOtherWrap, specializationOther);
    };

    const syncExperience = (saved = '') => {
      const experienced = candidateType?.value === 'Experienced';
      if (experienceWrap) experienceWrap.hidden = !experienced;
      [duration, previousRole].forEach((control) => {
        if (!control) return;
        control.disabled = !experienced;
        control.required = experienced;
      });
      if (experienced && saved) {
        if (sets.experienceDurations.includes(saved)) setValue(duration, saved);
        else {
          setValue(duration, 'Other');
          durationOther.value = saved;
        }
      }
      toggleOther(duration, durationOtherWrap, durationOther);
      if (!experienced) {
        if (duration) duration.value = '';
        if (durationOther) durationOther.value = '';
        if (previousRole) previousRole.value = '';
      }
    };

    qualification?.addEventListener('change', () => syncSpecialization(''));
    specialization?.addEventListener('change', () => toggleOther(specialization, specializationOtherWrap, specializationOther));
    candidateType?.addEventListener('change', () => syncExperience(''));
    duration?.addEventListener('change', () => toggleOther(duration, durationOtherWrap, durationOther));
    syncSpecialization(initial.specialization || '');
    syncExperience(initial.totalExperience || '');
  }

  function candidateSpecialization(form) {
    const selected = String(form.elements.specialization?.value || '').trim();
    return selected === 'Other' ? String(form.elements.specialization_other?.value || '').trim() : selected;
  }

  function candidateExperience(form) {
    if (form.elements.candidate_type?.value !== 'Experienced') return '';
    const selected = String(form.elements.total_experience?.value || '').trim();
    return selected === 'Other' ? String(form.elements.total_experience_other?.value || '').trim() : selected;
  }

  window.AadhyantRegistrationOptions = Object.freeze({
    sets,
    districtsByState,
    tradesByQualification,
    populate,
    setValue,
    initialize,
    setupStateDistrict,
    setupCandidateForm,
    candidateSpecialization,
    candidateExperience
  });

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => initialize());
  else initialize();
}());
