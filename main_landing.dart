import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../1_app_lock/app_lock_services/app_lock_global.dart';
import '../1_app_lock/app_lock_services/sp_service.dart';
import '../1_app_lock/app_lock_services/sp_service_keys.dart';
import '../appupdate/update_dialog.dart';
import '../auth/login.dart';
import '../global.dart';
import '../web_view.dart';
import '../web_view/bills_reports.dart';
import '../web_view/mrd_check_list.dart';
import 'app_lock/app_lock_service.dart';
import 'database_helper.dart';
import 'device_activity.dart';
import 'file_upload.dart';
import 'history.dart';
import 'histoty_new.dart';
import 'model_classes/model_op_patients.dart';
import 'model_classes/model_patient_details.dart';
import 'model_classes/model_userdetails.dart';
import 'settings_page.dart';
import 'traning.dart';
import 'user_activity_page.dart';
import 'user_logging.dart';

/// This Class indicates the Main Page which see the patient list ( List view and grid view)
class MainLanding extends StatefulWidget {
  const MainLanding({super.key});

  @override
  State<MainLanding> createState() => _MainLandingState();
}

class _MainLandingState extends State<MainLanding> with SingleTickerProviderStateMixin,WidgetsBindingObserver {
  final MyLocalAuthService _myLocalAuthService = MyLocalAuthService();
  final DatabaseHelper dbHelper = DatabaseHelper();
  bool isGridView = loginUserDetails[0].USER_PREFERENCES.viewPreferences.patientList == "CARD_VIEW"?true : false;
 /// Patient List For Binding
  List<ModelPatientDetails> filteredPatientsForBind = [];
  List filteredPatients = [];
  List filteredCaseSheet = [];
  /// OpPatients
  List<dynamic> opPatientData = [];

  String selectedPatientFilter = '';
  String? selectedNurseStationCd;
  String patientList = "IP";
  String? selectGender ="All";
  String? selectedConsultCd;

  WebViewController controller = WebViewController();

  bool isSwitched = false;

  TextEditingController controllerSearchPatient = TextEditingController();
  TextEditingController controllerSearchCaseSheet = TextEditingController();

  FocusNode f1 = FocusNode();
  FocusNode f2 = FocusNode();
  /// This Method Used For App Lock
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      isAppInactive = false;
      if (!mounted) return;
      if (!WebSocketService().isConnected) {
        WebSocketService().connect(macId:deviceId); // reconnect if needed
      }
      /// code for app-lock
      if (await _myLocalAuthService.checkDeviceSupportAndBiometricsAvailable()) {
        if (!isDialogShowing && !Global.isAuthenticated && Global.isAppLockEnabled) {
          _checkTimeDifference(context);
        }
      } else {
        // _callChildMethod();
        if (isDialogShowing) {
          Navigator.pop(context);
        }
        Global.isAppLockEnabled = false;
        // SpService.saveAppLockStatus(isAppLockEnabled: false);
        SpService.saveBoolValue(key: SpServiceKeys.isAppLockEnabled, value: Global.isAppLockEnabled);
      }
    }
    else if (state == AppLifecycleState.inactive){
      isAppInactive = true;
      WebSocketService().disconnect();
      // if(wifiTimer !=null) wifiTimer!.cancel();
    }
    else if (state == AppLifecycleState.paused) {
      isAppInactive = true;
      WebSocketService().disconnect();
      // if(wifiTimer !=null) wifiTimer!.cancel();

      /// code for app-lock
      Global.isAuthenticated = false;
      Global.updateLastPausedTime(DateTime.now());
    }
    else if (state == AppLifecycleState.detached){
      WebSocketService().disconnect();
      /// code for app-lock
      Global.updateLastPausedTime(DateTime.now());
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    WebSocketService().connect( macId: deviceId);
    if(licenceExpireDate=="105"){
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title:  Text(licenceExpireInfo,style: TextStyle(fontSize: 14,color: MAIN_TITLE_COLOR),),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Ok'),
              ),
            ],
          ),
        );
      });
    }

    /// FOR APP LOCK
    _initialiseTheGlobalVariables();
    if (kDebugMode) {
      print(globalFcmToken);
    }
    selectedPatientFilter =
    (loginUserDetails[0].USER_PREFERENCES.defaultPatListFilter.isNotEmpty)?
    loginUserDetails[0].USER_PREFERENCES.defaultPatListFilter:
    loginUserDetails[0].LOCATION_SETTINGS.defaultPatListFilter;
    AppSettings.saveData('ISDASHBOARD', true, SharedPreferenceIOType.BOOL);
    apiCall();
    // TODO: implement initState
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  /// Filter Search in Ip Patients
  void _filterSearchPatientResults(String query) {
    List<ModelPatientDetails> results = [];
    if (query.isEmpty) {
      results = mPatientDetails;
    }
    else {
      setState(() {
         results = mPatientDetails.where((patient) {
          final queryLower = query.toLowerCase();
          return patient.PATIENT_NAME1.toLowerCase().contains(queryLower) ||
              patient.ADMN_NO.toString().toLowerCase().contains(queryLower) ||
              patient.MOBILE_NO.toString().toLowerCase().contains(queryLower) ||
              patient.PATIENT_NAME.toString().toLowerCase().contains(queryLower) ||
              patient.CONSULTANT.toString().toLowerCase().contains(queryLower) ||
              patient.AGE.toString().toLowerCase().contains(queryLower) ||
              patient.BED.toString().toLowerCase().contains(queryLower) ||
              patient.UMR_NO.toLowerCase().contains(queryLower);
        }).toList();
      });
    }

    setState(() {
      filteredPatientsForBind = results;
    });
  }

  /// This Method uses for call Api Calls at one time
  apiCall() async {
    if(loginUserDetails[0].USER_PREFERENCES.defaultPatListFilter.isNotEmpty){
      await getIpData(loginUserDetails[0].USER_PREFERENCES.defaultPatListFilter=="ALL"?false:true, false);
    }
    else{
      await getIpData(loginUserDetails[0].LOCATION_SETTINGS.defaultPatListFilter=="ALL"?false:true, false);
    }

  }

  /// This Method get ip data
  Future<void> getIpData(bool myPatients, bool consult) async {
    Map<String, dynamic> payload = {};
//selectedConsultCd
    payload = {
      "host_id": loginUserDetails[0].HOST_ID,
      "flag": "ADMN",
      "ip_user_id": myPatients ? loginUserDetails[0].USER_ID : 0,
      "nursestation_cd": (selectedNurseStationCd == null) ? "" : selectedNurseStationCd,
      // "nursestation_cd":(myPatients&&selectedNurseStationCd=="ALL")? "":selectedNurseStationCd=="ALL"?"":selectedNurseStationCd,
      "ip_prefiex_text": "",
      "doctor_id":  consult ?selectedConsultCd:""
    };
    //var result = AbhaSettings.callRemotePostAPI(url:AbhaSettings.api["sessions"],payload,);
    var output = await callRemotePostAPI(
      payload,
      API['GET_ADMISSIONS_V1'],
      await headers(),
    );
    if (output != RestResponseabha.NODATARETRIEVEDFROMAPI.toString()&&output != RestResponseabha.LOGOUT.toString()) {
      var outputResponse = json.decode(output!);
      if (outputResponse["status"] == 200) {
        ipPatientData = outputResponse["data"];
        if(ipPatientData.isNotEmpty){
          filteredPatients = ipPatientData;
          mPatientDetails = (ipPatientData).map((dynamic model) {
            return ModelPatientDetails.fromJson(model);
          }).toList();
          filteredPatientsForBind = (ipPatientData).map((dynamic model) {
            return ModelPatientDetails.fromJson(model);
          }).toList();

          setState(() {
            patientDataUI = 1;
          });

        }
        else {
          setState(() {
            filteredPatientsForBind=[];
            patientDataUI = 2;
          });
        }

        // await getAllForms();
        // await getCaseSheet();
      }
      if (kDebugMode) {
        print(outputResponse);
      }
    }
    else if(output ==  RestResponseabha.LOGOUT.toString()){
      showLogoutAlertAndRedirect(context);
    }
    else {
      stopPreLoader(context);
      displayLongErrorToast('Unable to retrieve data. Please try again later.');
    }
  }

  /// This Method get Op Patients
  Future<void> getOpData() async {
    Map<String, dynamic> payload = {
      "host_id": loginUserDetails[0].HOST_ID,
      "flag": "CON",
      "ip_user_id": 361,
      "nursestation_cd": null,
      "ip_prefiex_text": ""
    };

    try {
      var output = await callRemotePostAPI(
        payload,
        API['GET_ADMISSIONS_V1'],
        await headers(),
      );

      if (output != RestResponseabha.NODATARETRIEVEDFROMAPI.toString()&&output != RestResponseabha.LOGOUT.toString()) {
        var outputResponse = json.decode(output!);
        if (outputResponse["status"] == 200) {
          setState(() {
            opPatientData = outputResponse["data"];
            modelOpPatients = (opPatientData).map((dynamic model) {
              return ModelClassOpPatients.fromJson(model);
            }).toList();
            patientDataUI = 3;
          });
        }
      }
      else if(output ==  RestResponseabha.LOGOUT.toString()){
        showLogoutAlertAndRedirect(context);
      }
      else {
        setState(() {
          patientDataUI = 2;
        });
        displayLongErrorToast('Unable to retrieve data. Please try again later.');
      }
    } catch (e) {
      setState(() {
        patientDataUI = 2;
      });
      displayLongErrorToast('Error retrieving data: $e');
    }
  }

  /// This Method Deep Search
  void deepSearch(String query) async {
    if (controllerSearchPatient.text.trim().length > 2) {
      setState(() {
        patientDataUI = 0;
      });
      Map<String, dynamic> payload = {};
      payload = {
        "host_id": loginUserDetails[0].HOST_ID,
        "ref_type": "ADMN",
        "ref_value": query
      };
      var output = await callRemotePostAPI(
        payload,
        API['DEEP_SEARCH'],
        await headers(),
      );
      if (output != RestResponseabha.NODATARETRIEVEDFROMAPI.toString()&&output != RestResponseabha.LOGOUT.toString()) {
        var outputResponse = json.decode(output!);
        if (outputResponse["status"] == 200) {
          if (outputResponse["data"].length == 0) {
            setState(() {
              setState(() {
                patientDataUI = 1;
              });
            });
          } else {
            setState(() {
              ipPatientData = outputResponse["data"];
              filteredPatients = ipPatientData;
              mPatientDetails = (ipPatientData).map((dynamic model) {
                return ModelPatientDetails.fromJson(model);
              }).toList();
              filteredPatientsForBind = (ipPatientData).map((dynamic model) {
                return ModelPatientDetails.fromJson(model);
              }).toList();
              patientDataUI = 1;
            });
          }

          // await getCaseSheet();
        }
        if (kDebugMode) {
          print(outputResponse);
        }
      }
      else if(output ==  RestResponseabha.LOGOUT.toString()){
        setState(() {
          showLogoutAlertAndRedirect(context);
        });
      }
      else {
        stopPreLoader(context);
        displayLongErrorToast('Unable to retrieve data. Please try again later.');
      }
    }
  }

  /// This Method Uses For get all forms
  Future<void> getAllForms() async {
    Map<String, dynamic> payload = {};
    payload = {"p_host_id": loginUserDetails[0].HOST_ID, "p_role_code": ""};
    //var result = AbhaSettings.callRemotePostAPI(url:AbhaSettings.api["sessions"],payload,);
    var output = await callRemotePostAPI(
      payload,
      API['GET_ALL_FORMS'],
      await headers(),
    );
    if (output != RestResponseabha.NODATARETRIEVEDFROMAPI.toString()&&output != RestResponseabha.LOGOUT.toString()) {
      var outputResponse = json.decode(output!);
      if (outputResponse["status"] == 200) {
        // mGetAllForms = ModelGetAllForms.fromJson(outputResponse["data"]??{});
        mGetAllForms = (outputResponse["data"] as List).map((dynamic model) {
          return ModelROLE_DOCUMENT_ACCESS.fromJson(model);
        }).toList();
        mGetAllFiltterForms =
            (outputResponse["data"] as List).map((dynamic model) {
          return ModelROLE_DOCUMENT_ACCESS.fromJson(model);
        }).toList();
        setState(() {
          allForms = outputResponse["data"];
        });
      }
      if (kDebugMode) {
        print(outputResponse);
      }
    }
    else if(output ==  RestResponseabha.LOGOUT.toString()){
      setState(() {
        showLogoutAlertAndRedirect(context);
      });
    }
    else {
      stopPreLoader(context);
      displayLongErrorToast('Unable to retrieve data. Please try again later.');
    }
  }

  int patientDataUI = 0;

  /// This Method Used For Common Card For Ip Patients List
  Widget _buildPatientCard(
      ModelPatientDetails patient, BuildContext context, int index) {
    return InkWell(
      onTap: () {
        setState(() {
          setState(() {
            // maindataState=2;
            selectedPatient = filteredPatients[index];
            selectedPatient1 = filteredPatientsForBind[index];
          });
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => const HistotyNew()));
          // maindataState=2;
          // selectedPatient=filteredPatients[index];
        });
      },
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.shade400),
        ),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child:Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Name and More Icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  /// ✅ Use `Expanded` inside `Row` (Correct)
                  Expanded(
                    child: Text(
                      patient.PATIENT_NAME,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    height: 20,
                    child: PopupMenuButton<String>(
                      color: Colors.white,
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        setState(() {
                          // maindataState=2;
                          selectedPatient = filteredPatients[index];
                          selectedPatient1 = filteredPatientsForBind[index];
                        });
                        if (kDebugMode) {
                          print("Selected: $value");
                        }
                        if (value == "PACS") {
                        }
                        else if (value == "Labreports") {
                         /* final String mrdUrl = "https://casesheetapp.doctor9.com/labReports/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.UMR_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BillsReports(url: mrdUrl),
                            ),
                          );*/
                          Navigator.push(context, MaterialPageRoute(builder: (context)=>WebViewPage1(type:"labReports",umr:selectedPatient1!.UMR_NO ,)));
                        }
                        else if (value == "Labresults") {
                          /*final String mrdUrl = "https://casesheetapp.doctor9.com/labresults/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.UMR_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BillsReports(url: mrdUrl),
                            ),
                          );*/
                          Navigator.push(context, MaterialPageRoute(builder: (context)=>WebViewPage1(type:"labReports",umr:selectedPatient1!.UMR_NO ,)));
                        }
                        else if (value == "BillsAndReceipts") {
                         /* final String mrdUrl = "https://casesheetapp.doctor9.com/bills/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.UMR_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BillsReports(url: mrdUrl),
                            ),
                          );*/
                          Navigator.push(context, MaterialPageRoute(builder: (context)=>WebViewPage1(type:"bills",umr:selectedPatient1!.UMR_NO ,)));
                        }
                        else if (value == "File Upload") {
                          Navigator.push(context, MaterialPageRoute(builder: (context)=>const FileUpload()));
                        }
                        else if (value == "MRDCheckList") {
                          /*final String mrdUrl = "https://casesheetapp.doctor9.com/mrdChecklist/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.ADMN_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WebViewPage(url: mrdUrl),
                            ),
                          );*/
                          Navigator.push(context, MaterialPageRoute(builder: (context)=>WebViewPage1(type:"mrdChecklist",umr:selectedPatient1!.UMR_NO ,)));
                        }
                        else if (value == "Critical alert") {
                          final String mrdUrl = "https://casesheetapp.doctor9.com/criticalAlerts/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.UMR_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WebViewPage(url: mrdUrl),
                            ),
                          );
                        }
                      },
                      itemBuilder: (BuildContext context) {
                       /* List menuItems = [
                          "File Upload",
                          "Lab Reports",
                          // "Lab Results",
                          "Bills And Receipts",
                          // "Critical alert"
                        ];*/
                        moreButtonItems;
                        return List.generate(
                            moreButtonItems.length, (index) {
                          return _buildMenuItem(
                              moreButtonItems[index],
                              index < moreButtonItems.length - 1);
                        });
                      },
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(),
              ///Age gender
              Text(
                "${patient.AGE}, ${patient.GENDER}, LOS: ${patient.LENGTHOFSTAY} Days",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              ///Addmissio no ,umr no
              Wrap(
                spacing: 2.0,
                runSpacing: 2.0,
                children: <Widget>[
                  if (patient.UMR_NO.isNotEmpty)
                    Text(patient.UMR_NO, style: SUB_TITLE),
                  if (patient.ADMN_NO.isNotEmpty)
                    Text('/${patient.ADMN_NO}', style: SUB_TITLE),
                ],
              ),
              const SizedBox(height: 4),
              ///ward name,bed,florid
              Wrap(
                spacing: 2.0,
                runSpacing: 2.0,
                children: <Widget>[
                  if (patient.WARD_NAME.isNotEmpty)
                    Text(patient.WARD_NAME, style: SUB_TITLE),
                  if (patient.BED != 0)
                    Text("/Bed:${patient.BED}", style: SUB_TITLE),
                  if (patient.FLOOR_CD.isNotEmpty)
                    Text("/${patient.FLOOR_CD}", style: SUB_TITLE),
                ],
              ),
              const SizedBox(height: 4),
              ///Mobile  no
              Visibility(
                visible: patient.MOBILE_NO.isNotEmpty,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    patient.MOBILE_NO,
                    style: SUB_TITLE,
                    maxLines: null,
                    softWrap: true,
                  ),
                ),
              ),
              Visibility(
                  visible: patient.MOBILE_NO.isNotEmpty,
                  child: const SizedBox(height: 4)),
              ///PRIMARY_DOC_NAME
              Wrap(
                spacing: 2.0,
                runSpacing: 2.0,
                children: [
                  Visibility(
                    visible: patient.PRIMARY_DOC_NAME.isNotEmpty,
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        patient.PRIMARY_DOC_NAME,
                        style: DR_SUB_TITLE,
                        maxLines: null,
                        softWrap: true,
                      ),
                    ),
                  ),
                  Visibility(
                    visible: patient.SECONDARY_DOC_NAME.isNotEmpty,
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(", ${patient.SECONDARY_DOC_NAME}",
                        style: DR_SUB_TITLE,
                        maxLines: null,
                        softWrap: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ///PATIENT_TYPE_NAME and ADMN_TYPE_NAME
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Visibility(
                    visible: patient.PATIENT_TYPE_NAME != "",
                    child: IntrinsicWidth(
                      child: Container(
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: patient.PATIENT_TYPE_NAME == "Cash"
                              ? Colors.green
                              : patient.PATIENT_TYPE_NAME == "CORPORATE"
                              ? Colors.blue
                              : Colors.orange,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Text(
                            patient.PATIENT_TYPE_NAME,
                            style: const  TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Visibility(
                      visible: patient.PATIENT_TYPE_NAME != "",
                      child: const SizedBox(width: 10)),
                  Visibility(
                    visible: patient.ADMN_TYPE_NAME != "",
                    child: IntrinsicWidth(
                      child: Container(
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.blue),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Text(
                            patient.ADMN_TYPE_NAME,
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5,),
                  Visibility(
                      visible:  patient.ADMN_STATUS=="D",
                      child: Text(
                        "Discharged",
                        style: DR_SUB_TITLE,
                      ))

                ],
              ),

            ],
          ),
        ),
      ),
    );
  }

  /// For Patient details (Lab Results)
  PopupMenuItem<String> _buildMenuItem(String text, bool showDivider) {
    return PopupMenuItem<String>(
      height: 10,
      value: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (showDivider)
            const Divider(), // Add divider only if `showDivider` is true
        ],
      ),
    );
  }
  /// This Method Uses For get All Forms And Images
  Future<void> getAllFormsAndImages() async {
    Map<String, dynamic> payload = {};
    payload = {
      "json_data": {
        "host_id": loginUserDetails[0].HOST_ID
      }
    };
    //var result = AbhaSettings.callRemotePostAPI(url:AbhaSettings.api["sessions"],payload,);
    var output = await callRemotePostAPI(
      payload,
      API['GET_IMAGES'],
      await headers(),
    );
    if (output != RestResponseabha.NODATARETRIEVEDFROMAPI.toString()&&output != RestResponseabha.LOGOUT.toString()) {
      var outputResponse = json.decode(output!);
      if (outputResponse["status"] == 200) {
        var data=outputResponse["data"];
        /*final existingRecords = await dbHelper.getAllCasesheets('documents');
        final currentLength = existingRecords.length;*/
        for (var item in data) {
          await dbHelper.insertData({
            'imageId': item["imageId"],
            'formId': item["formId"],
            'image_status': item["image_status"] ?? item["imageStatus"], // handles both keys
            'imageName': item["imageName"],
            'imageDescription': item["imageDescription"],
            'imageData': item["imageData"],
            'film': item["film"],
            'thumbnailData':item["thumbnailData"],
            'bindColumns': json.encode(item["bindColumns"]),
            'regionBlocks': json.encode(item["regionBlocks"]),
            'toolsProperties': json.encode(item["toolsProperties"]),
            'sequence': 0,
            'displayOrder': 0,
            'createBy': item["createBy"],
            'createDt': item["createDt"],
            'modifyBy': item["modifyBy"],
            'modifyDt': item["modifyDt"],
            'totalData': json.encode(item),
          }, 'documents');
        }
        // final data1 = await dbHelper.getAllCasesheets('documents');
        // print(data1);
        Navigator.pop(context);
      }
      if (kDebugMode) {
        print(outputResponse);
      }
    }
    else if(output ==  RestResponseabha.LOGOUT.toString()){
      setState(() {
        showLogoutAlertAndRedirect(context);
      });
    }
    else {
      stopPreLoader(context);
      displayLongErrorToast('Unable to retrieve data. Please try again later.');
    }
  }
  /// This Method Indicates the Update the Document
  Future<void> UpdatedDocuments() async {
    Map<String, dynamic> payload = {};
    final existingRecords = await dbHelper.getAllImageIdAndDate();
    final currentLength = existingRecords.length;
    payload = {
      "json_data": {
        "host_id": loginUserDetails[0].HOST_ID,
        "status":existingRecords
      }
    };
    //var result = AbhaSettings.callRemotePostAPI(url:AbhaSettings.api["sessions"],payload,);
    var output = await callRemotePostAPI(
      payload,
      API['GET_IMAGES'],
      await headers(),
    );
    if (output != RestResponseabha.NODATARETRIEVEDFROMAPI.toString()&&output != RestResponseabha.LOGOUT.toString()) {
      var outputResponse = json.decode(output!);
      if (outputResponse["status"] == 200) {
        var data=outputResponse["data"];
        for (var doc in data) {
          await dbHelper.insertOrUpdateDocument({
            'imageId': doc['imageId'],
            'formId': doc['formId'],
            'image_status': doc['image_status'] ?? doc['imageStatus'],
            'imageName': doc['imageName'],
            'imageDescription': doc['imageDescription'],
            'imageData': doc['imageData'],
            'film': doc['film'],
            'thumbnailData': json.encode(doc['thumbnailData']),
            'bindColumns': json.encode(doc['bindColumns']),
            'regionBlocks': json.encode(doc['regionBlocks']),
            'toolsProperties': json.encode(doc['toolsProperties']),
            'sequence': doc['sequence'] ?? 0,
            'displayOrder': doc['displayOrder'] ?? 0,
            'createBy': doc['createBy'],
            'createDt': doc['createDt'],
            'modifyBy': doc['modifyBy'],
            'modifyDt': doc['modifyDt'],
            'totalData': json.encode(doc),
          },"documents");
        }

        // final data1 = await dbHelper.getAllCasesheets('documents');
        // print(data1);
        Navigator.pop(context);
      }
      if (kDebugMode) {
        print(outputResponse);
      }
    }
    else if(output ==  RestResponseabha.LOGOUT.toString()){
      setState(() {
        showLogoutAlertAndRedirect(context);
      });
    }
    else {
      stopPreLoader(context);
      displayLongErrorToast('Unable to retrieve data. Please try again later.');
    }
  }

  /// This Method Used of see the Profile pop Up
  PopupMenuItem<int> _buildMenuItemPopUp(bool val,
      BuildContext context, int value, IconData icon, String text,
      {Color color = Colors.black}) {
    return PopupMenuItem<int>(
      height: 10,
      value: value,
      child: InkWell(
        onTap: () async {
          if (value == 3) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsBody(),));
          }
          else if (value == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const UserActivityScreen(),));
          }
          else if (value == 2) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const DeviceActivityScreen(),));
          }
          else if (value == 4) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const UserLogging(),));
          }
          else if (value == 8) {
            Navigator.pop(context);
            showUpdateDialog(
              context,
              version: versionNumber,
              notes: 'Bug fixes and performance improvements',
              isMandatory: false,
              note: true,
              onUpdate: () => downloadAndInstallUpdate(
                context,
                "https://nurstronic.doctor9.com/download/apk",
              ),
            );
          }
          else if (value == 9) {
            Navigator.pop(context);
            startPreloader(context);
            await getAllFormsAndImages();
          }
          else if (value == 10) {
            Navigator.pop(context);
            startPreloader(context);
            await UpdatedDocuments();
          }
          else if (value == 6)  {
            _showLogoutAlert(context);
          }
        },
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(fontSize: 14, color: color)),
          ],
        ),
      ),
    );
  }
  /// This Method Used For Patients Filter
  void filterPatients(String type) {
    setState(() {
      if (type == "ALL") {
        filteredPatientsForBind = filteredPatientsForBind;
        if (kDebugMode) {
          print(filteredPatientsForBind);
        } // Assuming you have a full patient list stored
      }
      else if (type == "ER") {
        filteredPatientsForBind = filteredPatientsForBind.where((patient) => patient.ADMN_TYPE_NAME == type).toList();
        if (kDebugMode) {
          print(filteredPatientsForBind);
        }
      }
      else {
        filteredPatientsForBind = filteredPatientsForBind.where((patient) => patient.ADMN_TYPE_NAME == type).toList();
        if (kDebugMode) {
          print(filteredPatientsForBind);
        }
      }
    });
  }
  /// This Method Used For Gender Filter
  void filterGender(String type){
    setState(() {
      if(type=="All"){
        filteredPatientsForBind=mPatientDetails;
        patientDataUI=1;
      }
      else if(type=="Male"){
        filteredPatientsForBind=mPatientDetails.where((patient) => patient.GENDER == "M").toList();
        patientDataUI=1;
      }
      else{
        filteredPatientsForBind=mPatientDetails.where((patient) => patient.GENDER == "F").toList();
        patientDataUI=1;
      }
    });
  }
  /// This Method Used For Doctor Filter
  void filterDoctor(String type){
    filteredPatientsForBind=mPatientDetails.where((patient) => patient.CONSULTANT == type).toList();
    patientDataUI=1;
  }
  /// THis Method get all Documents
  Future<void> appLogout() async {
    Map<String, dynamic> payload = {};
    payload = {
      "USER_NAME" : AppSettings.userLoginDetails.userNameController
    };
    //var result = AbhaSettings.callRemotePostAPI(url:AbhaSettings.api["sessions"],payload,);
    var output = await callRemotePostAPI(
      payload,
      API['LOGOUT'],
      await headers(),
    );
    if (output != RestResponseabha.NODATARETRIEVEDFROMAPI.toString()&&output != RestResponseabha.LOGOUT.toString()) {
      var outputResponse = json.decode(output!);
      if (outputResponse["status"] == 200) {
        stopPreLoader(context);
        AppSettings.clearSPExceptORG();
        WebSocketService().disconnect();
        Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage(title: 'DMS+'),),);
        setState(() {

        });
      }
      if (kDebugMode) {
        print(outputResponse);
      }
    }
    else if(output ==  RestResponseabha.LOGOUT.toString()){
      stopPreLoader(context);
      AppSettings.clearSPExceptORG();
      WebSocketService().disconnect();
      Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage(title: 'DMS+'),),);
      setState(() {

      });
    }
    else {
      stopPreLoader(context);
      displayLongErrorToast('Unable to log out at this time. Please try again.');
    }
  }
  /// This Method Uses For alert box while Logout Time
  void _showLogoutAlert(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Logout..?"),
          content: const Text("Are You Sure to Logout"),
          actions: [
            /// No
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("No"),
            ),

            /// Yes
            ElevatedButton(
              onPressed: () async {
                startPreloader(context);
                appLogout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text("Yes", style: TextStyle(fontFamily: commonFontFamily,color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Return false to prevent navigation back
        return false;
      },
      child: Scaffold(
        // backgroundColor: LIGHT_TITLE_COLOR,
        appBar: AppBar(
          backgroundColor: MAIN_TITLE_COLOR,
          centerTitle: true,
          title: Row(
            children: [
              Container(
                width: 60,
                height: 50,
                decoration: BoxDecoration(
                    color: white, borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image.asset(
                    "image/Company.jpg",
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SizedBox(width: 10,),
              Visibility(
                // visible: latestApkVersion!=versionNumber,
                visible: false,
                child: InkWell(
                  onTap: (){
                    showUpdateDialog(
                      context,
                      version: versionNumber,
                      notes: 'Bug fixes and performance improvements',
                      isMandatory: false,
                      note: true,
                      onUpdate: () => downloadAndInstallUpdate(
                        context,
                        "https://nurstronic.doctor9.com/download/apk",
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      Text("A new update is available.",style: TextStyle(fontSize: 14,color: white)),
                      Text("Tap to update now.",style: TextStyle(fontSize: 14,color: white))
                    ],
                  ),
                ),
              ),
              Visibility(
                visible: false,
                // visible: latestApkVersion==versionNumber,
                child:  Text("Version No: ${versionNumber}.",style: TextStyle(fontSize: 14,color: white)),
              )
            ],
          ),
          actions: [
            Visibility(
              visible: loginUserDetails[0].IS_TRAINED!=true,
              child: SizedBox(
                height: 27,
                child: ElevatedButton(
                    onPressed: () async {
                      Navigator.push(context, MaterialPageRoute(builder: (context)=>const Training()));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            12), // Adjust for smooth rounded corners
                      ),
                      padding:
                      const EdgeInsets.only(left: 4.0, right: 4.0),
                      // minimumSize: Size(60, 40),
                      // shape: CircleBorder()
                      // padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                    ),
                    child: Text(
                      "Training Status",
                      style: TextStyle(
                          color: MAIN_TITLE_COLOR, fontSize: 13),
                      textAlign: TextAlign.center,
                    )),
              ),
            ),
            const SizedBox(
              width: 10,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: PopupMenuButton<int>(
                shadowColor: Colors.grey,
                color: Colors.white,
                /*onSelected: (value) {
                  setState(() {});

                  /// LogOut
                  if (value == 6) {
                    _showLogoutAlert(context);
                  }

                  /// Settings
                  else if (value == 3) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsBody(),
                        ));
                  }

                  /// User Activity
                  else if (value == 1) {
                    Navigator.push(context, MaterialPageRoute(
                          builder: (context) => const UserActivityScreen(),
                        ));
                  }

                  /// device Activity
                  else if (value == 2) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DeviceActivityScreen(),
                        ));
                  }

                  /// user logging
                  else if (value == 4) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UserLogging(),
                        ));
                  }
                  else if (value == 8) {
                    Navigator.pop(context);
                    showUpdateDialog(
                      context,
                      version: versionNumber,
                      notes: 'Bug fixes and performance improvements',
                      isMandatory: false,
                      note: true,
                      onUpdate: () => downloadAndInstallUpdate(
                        context,
                        "https://nurstronic.doctor9.com/download/apk",
                      ),
                    );
                  }
                },*/
                offset: const Offset(0, 50), // Position below the avatar
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                itemBuilder: (context) => [
                  // User Profile Section
                  PopupMenuItem<int>(
                    enabled: false, // Disable selection
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loginUserDetails[0].DISPLAY_NAME,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black),
                        ),
                        Text(
                          loginUserDetails[0].ROLE_NAME,
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                 /* // Divider after Profile
                  const PopupMenuDivider(),

                  // Menu Items with Dividers
                  _buildMenuItemPopUp(
                      context, 1, Icons.person, "User Activity"),
                  const PopupMenuDivider(),
                  _buildMenuItemPopUp(
                      context, 2, Icons.devices, "Device Activity"),*/

                  _buildMenuItemPopUp(true,context, 9, Icons.auto_stories_outlined, "Download documents"),
                  const PopupMenuDivider(),
                  _buildMenuItemPopUp(true,context, 10, Icons.auto_stories_outlined, "Check For Doc Updates"),
                  const PopupMenuDivider(),
                  latestApkVersion==versionNumber?
                  _buildMenuItemPopUp(true,context, 7, Icons.system_update_alt, "Version.No: ${versionNumber}"):
                  _buildMenuItemPopUp(true,context, 8, Icons.system_update_alt, "New Update Available"),
                  const PopupMenuDivider(),
                  _buildMenuItemPopUp(true,context, 3, Icons.settings, "Settings"),
                  /*const PopupMenuDivider(),
                  _buildMenuItemPopUp(
                      context, 4, Icons.assignment, "User Logging"),*/
                  const PopupMenuDivider(),
                  //_buildMenuItemPopUp(5, Icons.upload_file, "File Upload"),

                  // Divider before Logout
                  //const PopupMenuDivider(),
                  _buildMenuItemPopUp(false,context, 6, Icons.logout, "Logout",),
                ],
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 20, // Profile image size
                      backgroundImage: AssetImage("image/profile.jpg"),
                    ),
                    Visibility(
                      visible: latestApkVersion!=versionNumber ,
                      child: Positioned(
                        left: 25,
                          bottom:25,
                          child: Icon(Icons.circle,color: RED,size: 15,)
                      ),
                    )
                  ],
                )
              ),
            ),
          ],
          automaticallyImplyLeading: false,

          // title: Text("EMR AMEERPET"),
        ),
        body: RefreshIndicator(
          onRefresh: () async{
            setState(() {
              patientDataUI=0;
            });
            apiCall();
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Column(
              children: [
                /// Search Bar
                Padding(
                  padding: const EdgeInsets.all(0.0),
                  child: Container(
                    height: 53,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(
                          width: patientDataUI == 3
                              ? MediaQuery.of(context).size.width * 0.97
                              : MediaQuery.of(context).size.width * 0.9,
                          child: TextField(
                            focusNode: f1,
                            controller: controllerSearchPatient,
                            onChanged: (value) {
                              setState(() {}); // Update UI when text changes
                              if (isSwitched) {
                                deepSearch(value);
                              } else {
                                _filterSearchPatientResults(value);
                              }
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.all(5),
                              prefixIcon:
                                  const Icon(Icons.search, color: Colors.grey),
                              suffixIcon: controllerSearchPatient.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          color: Colors.grey),
                                      onPressed: () {
                                        controllerSearchPatient.clear();
                                        _filterSearchPatientResults(
                                            ''); // Reset list
                                        setState(
                                            () {}); // Update UI after clearing text
                                      },
                                    )
                                  : null,
                              hintText: "Search Patient",
                              hintStyle: TextStyle(color: gray),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide:
                                    BorderSide(color: MAIN_TITLE_COLOR, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: const BorderSide(color: Colors.grey),
                              ),
                              filled: true,
                              fillColor: LIGHT_TITLE_COLOR,
                            ),
                            // enableInteractiveSelection: true,
                          ),
                        ),
                        patientDataUI != 3
                            ?
                            /// deep Search  Button (IP)
                            Transform.scale(
                                scale: 0.9, // Adjust this value to reduce size
                                child: Switch(
                                  value: isSwitched,
                                  activeColor: MAIN_TITLE_COLOR,
                                  onChanged: (value) {
                                    setState(() {
                                      isSwitched = value;
                                    });
                                    if (!isSwitched) {
                                      setState(() {
                                        patientDataUI = 0;
                                      });
                                      getIpData(true, false);
                                    }
                                  },
                                ),
                              )
                            : const Text(""),
                      ],
                    ),
                  ),
                ),
                ///filter
                Padding(
                  padding: const EdgeInsets.only(right: 10.0, left: 15.0, top: 5.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                     Row(
                       children: [
                         /// My patients, all Patients
                         Container(
                           width: MediaQuery.of(context).size.width * 0.15, // Ensures finite width
                           height: MediaQuery.of(context).size.height * 0.03, // Fixed height
                           decoration: BoxDecoration(
                             borderRadius: BorderRadius.circular(5),
                             border: Border.all(color: Colors.grey),
                           ),
                           padding: const EdgeInsets.symmetric(horizontal: 8),
                           child: DropdownButtonHideUnderline(
                             child: DropdownButton<String>(
                               value: selectedPatientFilter,
                               isExpanded: true,
                               icon: const Icon(Icons.arrow_drop_down,
                                   color: Colors.black),
                               items: const [
                                 DropdownMenuItem(
                                     value: "ALL",
                                     child: Text(
                                       "All Patients",
                                       style: TextStyle(
                                           fontSize: 12,
                                           fontWeight: FontWeight.normal),
                                     )),
                                 DropdownMenuItem(
                                     value: "MY_PATIENTS",
                                     child: Text(
                                       "My Patients",
                                       style:   TextStyle(
                                           fontSize: 12,
                                           fontWeight: FontWeight.normal),
                                     )),
                               ],
                               onChanged: (String? newValue) {
                                 if (newValue != null) {
                                   setState(() {
                                     patientDataUI=0;
                                     selectedPatientFilter = newValue;
                                     selectedConsultCd=null;
                                   });
                                   getIpData(newValue == "MY_PATIENTS", false);
                                 }
                               },
                               dropdownColor: Colors.white,
                             ),
                           ),
                         ),
                         const SizedBox(
                           width: 10,
                         ),
                         /// Gender
                         Container(
                           width: MediaQuery.of(context).size.width * 0.095,
                           height: MediaQuery.of(context).size.height * 0.03,
                           child: DecoratedBox(
                             decoration: BoxDecoration(
                               border: Border.all(color: Colors.grey), // Grey border
                               borderRadius:
                               BorderRadius.circular(5), // Rounded corners
                               //color: Colors.white, // Background color
                             ),
                             child: Padding(
                               padding: const EdgeInsets.symmetric(
                                   horizontal: 8), // Reduce padding to fit height
                               child: DropdownButtonHideUnderline(
                                 child: DropdownButton<String>(
                                   value: selectGender,
                                   onChanged: (String? newValue) async {
                                     if (newValue != null) {
                                       setState(() {
                                         selectGender = newValue;
                                         patientDataUI = 0;
                                       });
                                       filterGender(selectGender!);
                                     }
                                   },
                                   items: ["All","Male", "Female"].map((String value) {
                                     return DropdownMenuItem<String>(
                                       value: value,
                                       child: Text(
                                         value,
                                         style: const TextStyle(
                                           color:
                                           Colors.black, // Instant color update
                                           fontSize: 12, // Adjust text size
                                         ),
                                       ),
                                     );
                                   }).toList(),
                                   isExpanded: true,
                                   iconSize: 20, // Reduce icon size if needed
                                   menuMaxHeight: 250, // Maximum dropdown height
                                   style:
                                   const TextStyle(fontSize: 14), // Text style
                                   icon: const Icon(
                                     Icons.arrow_drop_down, //color: Colors.black
                                   ), // Dropdown icon
                                   //dropdownColor: Colors.white, // Background color of the dropdown
                                 ),
                               ),
                             ),
                           ),
                         ),
                         /// DropDown for consult
                         Visibility(
                             visible:  patientDataUI != 3 &&loginUserDetails[0].ROLE_NAME=="NURSE",
                             // visible: loginUserDetails[0].CONSULTS.isNotEmpty,
                             child: Row(
                               children: [
                                 /// SizedBox
                                 const SizedBox(
                                   width: 10,
                                 ),
                                 /// DropDown for consult
                                 SizedBox(
                                   width: MediaQuery.of(context).size.width * 0.22,
                                   height: MediaQuery.of(context).size.height * 0.03,
                                   child: DecoratedBox(
                                     decoration: BoxDecoration(
                                       border: Border.all(
                                           color: Colors.grey), // Grey border
                                       borderRadius: BorderRadius.circular(
                                           5), // Optional: Rounded corners
                                     ),
                                     child: Padding(
                                       padding:
                                       const EdgeInsets.symmetric(horizontal: 8),
                                       child: DropdownButtonHideUnderline(
                                         child: DropdownButton<String>(
                                           value: selectedConsultCd,
                                           hint: Text("Select Doctor", style: TextStyle(color: gray, fontSize: 15),),
                                           isExpanded: true,
                                           items: loginUserDetails[0].CONSULTS.map((station) {
                                             return DropdownMenuItem<String>(
                                               value: station.doctor_name,
                                               child: Text(
                                                 station.doctor_name,
                                                 style: const TextStyle(
                                                     fontSize: 13,
                                                     fontWeight: FontWeight.normal),
                                               ),
                                             );
                                           }).toList(),
                                           onChanged: (value) {
                                             setState(() {
                                               selectedConsultCd = value;
                                               patientDataUI = 0;
                                             });
                                             filterDoctor(value!);
                                             /*setState(() {
                                               selectedNurseStationCd = null;
                                               selectedConsultCd = value;
                                               getIpData(false, true);
                                             });*/
                                           },
                                           menuMaxHeight: 250,
                                         ),
                                       ),
                                     ),
                                   ),
                                 )
                               ],
                             )
                         ),
                         ///Dropdown for IP,OP
                         Visibility(
                           visible: false,
                           child: Row(
                             children: [
                               /// SizedBox
                               const SizedBox(
                                 width: 10,
                               ),
                               ///Dropdown for IP,OP
                               SizedBox(
                                 width: MediaQuery.of(context).size.width * 0.08,
                                 height: MediaQuery.of(context).size.height * 0.03,
                                 child: DecoratedBox(
                                   decoration: BoxDecoration(
                                     border: Border.all(color: Colors.grey), // Grey border
                                     borderRadius:
                                     BorderRadius.circular(5), // Rounded corners
                                     //color: Colors.white, // Background color
                                   ),
                                   child: Padding(
                                     padding: const EdgeInsets.symmetric(
                                         horizontal: 8), // Reduce padding to fit height
                                     child: DropdownButtonHideUnderline(
                                       child: DropdownButton<String>(
                                         value: patientList,
                                         onChanged: (String? newValue) async {
                                           if (newValue != null) {
                                             if (newValue == "IP") {
                                               setState(() {
                                                 patientList = newValue;
                                                 patientDataUI = 0;
                                               });
                                               await getIpData(true, false);
                                             } else {
                                               setState(() {
                                                 patientList = newValue;
                                                 patientDataUI = 0;
                                               });
                                               await getOpData();
                                             }
                                           }
                                         },
                                         items: ["IP", "OP"].map((String value) {
                                           return DropdownMenuItem<String>(
                                             value: value,
                                             child: Text(
                                               value,
                                               style: const TextStyle(
                                                 color:
                                                 Colors.black, // Instant color update
                                                 fontSize: 12, // Adjust text size
                                               ),
                                             ),
                                           );
                                         }).toList(),
                                         isExpanded: true,
                                         iconSize: 20, // Reduce icon size if needed
                                         menuMaxHeight: 250, // Maximum dropdown height
                                         style:
                                         const TextStyle(fontSize: 14), // Text style
                                         icon: const Icon(
                                           Icons.arrow_drop_down, //color: Colors.black
                                         ), // Dropdown icon
                                         //dropdownColor: Colors.white, // Background color of the dropdown
                                       ),
                                     ),
                                   ),
                                 ),
                               ),
                             ],
                           ),
                         ),
                         /// Nurse Station
                         Visibility(
                             visible:  patientDataUI != 3 &&loginUserDetails[0].ROLE_NAME=="NURSE",
                             child:  Row(
                               children: [
                                 /// Sized box
                                 const SizedBox(
                                   width: 10,
                                 ),
                                 /// DropDown for NURSE_STATIONS
                                 SizedBox(
                                   width: MediaQuery.of(context).size.width * 0.16,
                                   height: MediaQuery.of(context).size.height * 0.03,
                                   child: DecoratedBox(
                                     decoration: BoxDecoration(
                                       border: Border.all(
                                           color: Colors.grey), // Grey border
                                       borderRadius: BorderRadius.circular(
                                           5), // Optional: Rounded corners
                                     ),
                                     child: Padding(
                                       padding: const EdgeInsets.symmetric(
                                           horizontal:
                                           8), // Reduce padding to fit height
                                       child: DropdownButtonHideUnderline(
                                         // Hides default dropdown underline
                                         child: DropdownButton<String>(
                                           value: selectedNurseStationCd,
                                           hint: const Text("Select NS", style: TextStyle(
                                                 color: Colors.grey,
                                                 fontSize:
                                                 14), // Adjust font size if needed
                                           ),
                                           isExpanded: true,
                                           iconSize: 20, // Reduce icon size if needed
                                           items: loginUserDetails[0].NURSE_STATIONS.map((station) {
                                             return DropdownMenuItem<String>(
                                               value: station.NURSE_STATION_CD,
                                               child: Text(
                                                 station.NURSE_STATION_NAME,
                                                 style: const TextStyle(
                                                     fontSize: 12,
                                                     fontWeight: FontWeight
                                                         .normal), // Adjust text size
                                               ),
                                             );
                                           }).toList(),
                                           onChanged: (value) {
                                             setState(() {
                                               // selectedConsultCd = null;
                                               selectedNurseStationCd = value;
                                             });
                                             getIpData(false, false);
                                           },
                                           menuMaxHeight: 250,
                                         ),
                                       ),
                                     ),
                                   ),
                                 ),
                               ],
                             )
                         ),
                       ],
                     ),
                     Row(
                       children: [
                         Visibility(
                           visible: filteredPatientsForBind.isNotEmpty,
                           child: Container(
                             decoration: BoxDecoration(
                                 borderRadius: BorderRadius.circular(20),
                               color:MAIN_TITLE_COLOR
                             ),
                             child: Padding(
                               padding: const EdgeInsets.all(8.0),
                               child: Text("${filteredPatientsForBind.length}",style: TextStyle(color: white),),
                             ),
                           ),
                         ),
                         IconButton(
                             onPressed: (){
                           setState(() {
                             patientDataUI=0;
                             selectedNurseStationCd=null;
                             patientList = "IP";
                             selectedConsultCd=null;
                             selectGender="All";
                             selectedPatientFilter =
                             (loginUserDetails[0].USER_PREFERENCES.defaultPatListFilter.isNotEmpty)?
                             loginUserDetails[0].USER_PREFERENCES.defaultPatListFilter:
                             loginUserDetails[0].LOCATION_SETTINGS.defaultPatListFilter;
                             apiCall();

                           });
                         },
                             icon: const Icon(Icons.autorenew_rounded)
                         ),
                         ToggleButtons(
                           borderRadius: BorderRadius.circular(2),
                           selectedBorderColor: MAIN_TITLE_COLOR,
                           selectedColor: Colors.white,
                           fillColor: MAIN_TITLE_COLOR,
                           color: Colors.black,
                           constraints: const BoxConstraints(
                               minHeight: 30,
                               minWidth: 40), // Adjust height and width
                           isSelected: [!isGridView, isGridView],
                           onPressed: (index) {
                             setState(() {
                               isGridView = index == 1;
                             });
                           },
                           children: const [
                             SizedBox(
                               height: 24, // Decrease height
                               child: Padding(
                                 padding: EdgeInsets.symmetric(horizontal: 4),
                                 child:
                                 Icon(Icons.list, size: 18), // Adjust icon size
                               ),
                             ),
                             SizedBox(
                               height: 24, // Decrease height
                               child: Padding(
                                 padding: EdgeInsets.symmetric(horizontal: 4),
                                 child: Icon(Icons.grid_view,
                                     size: 18), // Adjust icon size
                               ),
                             ),
                           ],
                         ),
                       ],
                     )
                    ],
                  ),
                ),
                Expanded(
                  child: isGridView ? gridViewData() : ipData(),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }


  /// This Method Used For Ip Patients UI In Grid View
  Widget gridViewData() {
    if (patientDataUI == 0) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    /// IP Patients
    else if (patientDataUI == 1) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: filteredPatientsForBind.isNotEmpty?
          GridView.builder(
            shrinkWrap: true, // Ensures GridView takes only required space
            physics: const NeverScrollableScrollPhysics(), // Disable scrolling if needed
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.080, // Adjust for better height control
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: filteredPatientsForBind.length,
            itemBuilder: (context, index) {
              return _buildPatientCard(
                  filteredPatientsForBind[index], context, index);
            },
          ):
          Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height *0.4),
                Text("No Patient's Found"),
              ],
            ),
          ),
        ),
      );
    }
    /// No Data
    else if (patientDataUI == 2) {
      return const Center(
        child: Text("No Patients Found"),
      );
    }
    /// Op Patients
    else {
      return SingleChildScrollView(
        child: GestureDetector(
          onTap: () {
            f1.unfocus();
          },
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              children: [
                modelOpPatients.isEmpty?
                const Center(
                  child: Text("No Patient's Found"),
                ):
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: modelOpPatients.length,
                  itemBuilder: (context, index) {
                    var patient = modelOpPatients[index];
                    return Card(
                      color: white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRect(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            radius: 800,
                            splashColor: Theme.of(context)
                                .colorScheme
                                .inversePrimary
                                .withOpacity(0.2),
                            onLongPress: () {},
                            onTap: () {
                              displayLongSucessToast(
                                  "The screens will be under development Phase.");
                            },
                            child: Container(
                              width: MediaQuery.of(context).size.width,
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  /// Patient Name
                                  SizedBox(
                                    height: 25,
                                    child: Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                      children: <Widget>[
                                        /// Name
                                        Text(
                                          patient.PATIENT_NAME,
                                          overflow: TextOverflow.visible,
                                          maxLines: 2,
                                          softWrap: true,
                                          style: EndDrawerPatientName(),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.center,
                                          crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                          children: [
                                            Visibility(
                                              visible:
                                              patient.PATIENT_TYPE_CD != "",
                                              child: IntrinsicWidth(
                                                child: Container(
                                                  height: 20,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                    BorderRadius.circular(
                                                        2),
                                                    color: patient
                                                        .PATIENT_TYPE_CD ==
                                                        "Cash"
                                                        ? Colors.green
                                                        : patient.PATIENT_TYPE_CD ==
                                                        "CORPORATE"
                                                        ? Colors.blue
                                                        : Colors.orange,
                                                  ),
                                                  child: Padding(
                                                    padding:const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6.0),
                                                    child: Text(
                                                      patient.PATIENT_TYPE_CD,
                                                      style:   TextStyle(fontFamily: commonFontFamily,
                                                          color: Colors.white),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Visibility(
                                                visible:
                                                patient.PATIENT_TYPE_CD != "",
                                                child: const SizedBox(width: 10,)),
                                            patient.TOKEN_NO.isNotEmpty
                                                ? Container(
                                              width: 70,
                                              alignment: Alignment.center,
                                              padding:
                                              const EdgeInsets.all(2.0),
                                              decoration: BoxDecoration(
                                                color: MAIN_TITLE_COLOR,
                                                borderRadius:
                                                BorderRadius.circular(
                                                    8),
                                                border: Border.all(
                                                    color:
                                                    Colors.black12),
                                              ),
                                              child: Text(
                                                "${patient.TOKEN_NO}",
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10),
                                              ),
                                            )
                                                : const SizedBox(width: 70),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width:
                                    MediaQuery.of(context).size.width * .93,
                                    child: Row(
                                      //mainAxisAlignment: filteredPatientsForBind[index].ADMN_NO != "" ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                                      children: <Widget>[
                                        /// UMR,PAT_MOBILE_NO
                                        Visibility(
                                          visible: patient.UMR_NO != "",
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "${patient.UMR_NO}/",
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),

                                        ///gender
                                        Visibility(
                                          visible: patient.GENDER_CD != "",
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "${patient.GENDER_CD}/",
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),

                                        ///  Formated DAte
                                        Row(
                                          children: [
                                            Visibility(
                                              visible: patient.BILL_NO != "",
                                              child: Align(
                                                child: Text(
                                                  patient.BILL_NO,
                                                  style: SUB_TITLE.copyWith(
                                                      color: BLACK),
                                                ),
                                              ),
                                            ),
                                            Visibility(
                                              visible:
                                              patient.PAT_MOBILE_NO != 0,
                                              child: Align(
                                                child: Text(
                                                  " ${patient.PAT_MOBILE_NO}",
                                                  style: SUB_TITLE.copyWith(
                                                      color: BLACK),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: <Widget>[
                                      Row(
                                        children: [
                                          Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "Dr. ${patient.DOCTOR_NAME}",
                                              style: DR_SUB_TITLE,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                )
              ],
            ),
          ),
        ),
      );
    }

  }

  /// This Method Used For Ip Patients UI In List View
  Widget ipData() {
    if (patientDataUI == 0) {
      return  Center(
        child: CircularProgressIndicator(color: MAIN_TITLE_COLOR,),
      );
    }

    /// IP Patients
    else if (patientDataUI == 1) {
      return SingleChildScrollView(
        child: GestureDetector(
          onTap: () {
            f1.unfocus();
          },
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              children: [
                filteredPatientsForBind.isEmpty?
                 Center(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height *0.4),
                      Text("No Patient's Found"),
                    ],
                  ),
                ):
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: filteredPatientsForBind.length,
                  itemBuilder: (context, index) {
                    return Card(
                      color: white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRect(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            radius: 800,
                            splashColor: Theme.of(context).colorScheme.inversePrimary.withOpacity(0.2),
                            child: Container(
                              width: MediaQuery.of(context).size.width,
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  /// Patient Name
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: <Widget>[
                                      /// Patient Name
                                      Expanded(
                                        child: Text(
                                          filteredPatientsForBind[index].PATIENT_NAME,
                                          overflow: TextOverflow.visible,
                                          maxLines: 2,
                                          softWrap: true,
                                          style: EndDrawerPatientName(),
                                        ),
                                      ),
                                      /// Cas/ TPA/ Corporate
                                      Visibility(
                                        visible: filteredPatientsForBind[index]
                                            .PATIENT_TYPE_NAME !=
                                            "",
                                        child: IntrinsicWidth(
                                          child: Container(
                                            height: 20,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                              BorderRadius.circular(2),
                                              color: filteredPatientsForBind[
                                              index]
                                                  .PATIENT_TYPE_NAME ==
                                                  "Cash"
                                                  ? Colors.green
                                                  : filteredPatientsForBind[
                                              index]
                                                  .PATIENT_TYPE_NAME ==
                                                  "CORPORATE"
                                                  ? Colors.blue
                                                  : Colors.orange,
                                            ),
                                            child: Padding(
                                              padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6.0),
                                              child: Text(
                                                filteredPatientsForBind[index]
                                                    .PATIENT_TYPE_NAME,
                                                style:   TextStyle(fontFamily: commonFontFamily,
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Visibility(
                                          visible:
                                          filteredPatientsForBind[index]
                                              .PATIENT_TYPE_NAME !=
                                              "",
                                          child: const SizedBox(width: 10)),
                                      /// Patient type IP/ER
                                      Visibility(
                                        visible: filteredPatientsForBind[index]
                                            .ADMN_TYPE_NAME !=
                                            "",
                                        child: IntrinsicWidth(
                                          child: Container(
                                            height: 20,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                              BorderRadius.circular(2),
                                              border: Border.all(
                                                  color: Colors.blue),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                              child: Text(
                                                filteredPatientsForBind[index]
                                                    .ADMN_TYPE_NAME,
                                                style:   TextStyle(fontFamily: commonFontFamily,
                                                    color: Colors.blue),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      /// More
                                      SizedBox(
                                        height: 20,
                                        child: PopupMenuButton<String>(
                                          color: Colors.white,
                                          padding: EdgeInsets.zero,
                                          onSelected: (value) {
                                            setState(() {
                                              // maindataState=2;
                                              selectedPatient = filteredPatients[index];
                                              selectedPatient1 = filteredPatientsForBind[index];
                                            });
                                            if (kDebugMode) {
                                              print("Selected: $value");
                                            }
                                            if (value == "PACS") {
                                            }
                                            else if (value == "Labreports") {
                                              /* final String mrdUrl = "https://casesheetapp.doctor9.com/labReports/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.UMR_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BillsReports(url: mrdUrl),
                            ),
                          );*/
                                              Navigator.push(context, MaterialPageRoute(builder: (context)=>WebViewPage1(type:"labReports",umr:selectedPatient1!.UMR_NO ,)));
                                            }
                                            else if (value == "Labresults") {
                                              /*final String mrdUrl = "https://casesheetapp.doctor9.com/labresults/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.UMR_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BillsReports(url: mrdUrl),
                            ),
                          );*/
                                              Navigator.push(context, MaterialPageRoute(builder: (context)=>WebViewPage1(type:"labReports",umr:selectedPatient1!.UMR_NO ,)));
                                            }
                                            else if (value == "BillsAndReceipts") {
                                              /* final String mrdUrl = "https://casesheetapp.doctor9.com/bills/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.UMR_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BillsReports(url: mrdUrl),
                            ),
                          );*/
                                              Navigator.push(context, MaterialPageRoute(builder: (context)=>WebViewPage1(type:"bills",umr:selectedPatient1!.UMR_NO ,)));
                                            }
                                            else if (value == "File Upload") {
                                              Navigator.push(context, MaterialPageRoute(builder: (context)=>const FileUpload()));
                                            }
                                            else if (value == "MRDCheckList") {
                                              /*final String mrdUrl = "https://casesheetapp.doctor9.com/mrdChecklist/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.ADMN_NO}";
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WebViewPage(url: mrdUrl),
                            ),
                          );*/
                                              Navigator.push(context, MaterialPageRoute(builder: (context)=>WebViewPage1(type:"mrdChecklist",umr:selectedPatient1!.UMR_NO ,)));
                                            }
                                            else if (value == "Critical alert") {
                                              final String mrdUrl = "https://casesheetapp.doctor9.com/criticalAlerts/m/${loginUserDetails[0].HOST_ID}/${selectedPatient1!.UMR_NO}";
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => WebViewPage(url: mrdUrl),
                                                ),
                                              );
                                            }
                                          },
                                          itemBuilder: (BuildContext context) {
                                           /* List menuItems = [
                                              "File Upload",
                                              "Lab Reports",
                                              // "Lab Results",
                                              "Bills And Receipts",
                                              // "Critical alert"
                                            ];*/
                                            moreButtonItems;
                                            return List.generate(
                                                moreButtonItems.length, (index) {
                                              return _buildMenuItem(
                                                  moreButtonItems[index],
                                                  index < moreButtonItems.length - 1);
                                            });
                                          },
                                          icon: const Icon(Icons.more_vert),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: 3,
                                  ),

                                  /// IP Number and Formatted DAte
                                  SizedBox(
                                    width:
                                    MediaQuery.of(context).size.width * .93,
                                    child: Row(
                                      //mainAxisAlignment: filteredPatientsForBind[index].ADMN_NO != "" ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                                      children: <Widget>[
                                        /// IP Number
                                        Visibility(
                                          visible:
                                          filteredPatientsForBind[index]
                                              .ADMN_NO !=
                                              "",
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "${filteredPatientsForBind[index].ADMN_NO}/",
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),
                                        Visibility(
                                          visible:
                                          filteredPatientsForBind[index]
                                              .UMR_NO !=
                                              "",
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "${filteredPatientsForBind[index].UMR_NO}/",
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),

                                        ///  Formated DAte
                                        Row(
                                          children: [
                                            Visibility(
                                              visible: filteredPatientsForBind[
                                              index]
                                                  .FORMATED_ADMN_DT_TIME !=
                                                  "",
                                              child: Align(
                                                child: Text(
                                                  filteredPatientsForBind[index]
                                                      .FORMATED_ADMN_DT_TIME,
                                                  style: SUB_TITLE.copyWith(
                                                      color: BLACK),
                                                ),
                                              ),
                                            ),
                                            Visibility(
                                              visible:
                                              filteredPatientsForBind[index]
                                                  .LENGTHOFSTAY !=
                                                  0,
                                              child: Align(
                                                child: Text(
                                                  "/ Los:${filteredPatientsForBind[index].LENGTHOFSTAY}",
                                                  style: SUB_TITLE.copyWith(
                                                      color: BLACK),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 3,
                                  ),

                                  /// WARD_NAME,BED,FLOOR_CD
                                  SizedBox(
                                    width:
                                    MediaQuery.of(context).size.width * .93,
                                    child: Row(
                                      // mainAxisAlignment: filteredPatientsForBind[index].ADMN_NO != "" ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                                      children: <Widget>[
                                        /// WARD_NAME,BED,FLOOR_CD
                                        Visibility(
                                          visible:
                                          filteredPatientsForBind[index]
                                              .WARD_NAME !=
                                              "",
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              filteredPatientsForBind[index]
                                                  .WARD_NAME,
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),

                                        /// BED
                                        Visibility(
                                          visible:
                                          filteredPatientsForBind[index].BED !=0,
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "/Bed:${filteredPatientsForBind[index].BED}",
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),

                                        /// FLOOR_CD
                                        Visibility(
                                          visible:
                                          filteredPatientsForBind[index]
                                              .FLOOR_CD !=
                                              "",
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "/${filteredPatientsForBind[index].FLOOR_CD}",
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 3,
                                  ),

                                  /// Mobile Number
                                  Visibility(
                                    visible: filteredPatientsForBind[index].MOBILE_NO.isNotEmpty,
                                    child: Column(
                                      children: <Widget>[
                                        const SizedBox(
                                          height: 2,
                                        ),
                                        Row(
                                          children: <Widget>[
                                            Row(
                                              children: [
                                                const Align(
                                                  alignment: Alignment.topLeft,
                                                  child: Icon(
                                                    Icons.phone,
                                                    size: 10,
                                                    color: Colors.red,
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: 2,
                                                ),
                                                Align(
                                                  alignment: Alignment.topLeft,
                                                  child: Text(
                                                    filteredPatientsForBind[index].MOBILE_NO,
                                                    style: SUB_TITLE.copyWith(
                                                        color: BLACK),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  /// Dr Name
                                  Visibility(
                                    // visible: loginUserDetails[0].USER_NAME != "consult",
                                    visible: true,
                                    child: Column(
                                      children: <Widget>[
                                        const SizedBox(
                                          height: 2,
                                        ),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: <Widget>[
                                            Row(
                                              children: [
                                                Align(
                                                  alignment: Alignment.topLeft,
                                                  child: Text(
                                                    filteredPatientsForBind[index].PRIMARY_DOC_NAME,
                                                    style: DR_SUB_TITLE,
                                                  ),
                                                ),
                                                Visibility(
                                                  visible: filteredPatientsForBind[index].SECONDARY_DOC_NAME.isNotEmpty,
                                                  child: Align(
                                                    alignment: Alignment.topLeft,
                                                    child: Text(", ${filteredPatientsForBind[index].SECONDARY_DOC_NAME}",
                                                      style: DR_SUB_TITLE,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  filteredPatientsForBind[index].ADMN_STATUS=="D"?
                                  Text(
                                    "discharged",
                                    style: DR_SUB_TITLE,
                                  ):const Text(""),
                                ],
                              ),
                            ),
                            onLongPress: () {},
                            onTap: () {
                              setState(() {
                                setState(() {
                                  // maindataState=2;
                                  selectedPatient = filteredPatients[index];
                                  selectedPatient1 =
                                  filteredPatientsForBind[index];
                                });
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => const HistotyNew()));
                                // maindataState=2;
                                // selectedPatient=filteredPatients[index];
                              });
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    /// No Data
    else if (patientDataUI == 2) {
      return const Center(
        child: Text("No Patients Found"),
      );
    }

    /// Op Patients
    else {
      return SingleChildScrollView(
        child: GestureDetector(
          onTap: () {
            f1.unfocus();
          },
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              children: [
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: modelOpPatients.length,
                  itemBuilder: (context, index) {
                    var patient = modelOpPatients[index];
                    return Card(
                      color: white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRect(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            radius: 800,
                            splashColor: Theme.of(context)
                                .colorScheme
                                .inversePrimary
                                .withOpacity(0.2),
                            onLongPress: () {},
                            onTap: () {
                              displayLongSucessToast(
                                  "The screens will be under development Phase.");
                            },
                            child: Container(
                              width: MediaQuery.of(context).size.width,
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  /// Patient Name
                                  SizedBox(
                                    height: 25,
                                    child: Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                      children: <Widget>[
                                        /// Name
                                        Text(
                                          patient.PATIENT_NAME,
                                          overflow: TextOverflow.visible,
                                          maxLines: 2,
                                          softWrap: true,
                                          style: EndDrawerPatientName(),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                          MainAxisAlignment.center,
                                          crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                          children: [
                                            Visibility(
                                              visible:
                                              patient.PATIENT_TYPE_CD != "",
                                              child: IntrinsicWidth(
                                                child: Container(
                                                  height: 20,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                    BorderRadius.circular(
                                                        2),
                                                    color: patient
                                                        .PATIENT_TYPE_CD ==
                                                        "Cash"
                                                        ? Colors.green
                                                        : patient.PATIENT_TYPE_CD ==
                                                        "CORPORATE"
                                                        ? Colors.blue
                                                        : Colors.orange,
                                                  ),
                                                  child: Padding(
                                                    padding:   const EdgeInsets.symmetric(
                                                        horizontal: 6.0),
                                                    child: Text(
                                                      patient.PATIENT_TYPE_CD,
                                                      style:   TextStyle(fontFamily: commonFontFamily,
                                                          color: Colors.white),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Visibility(
                                                visible:
                                                patient.PATIENT_TYPE_CD !=
                                                    "",
                                                child: const SizedBox(
                                                  width: 10,
                                                )),
                                            patient.TOKEN_NO.isNotEmpty
                                                ? Container(
                                              width: 70,
                                              alignment: Alignment.center,
                                              padding:
                                              const EdgeInsets.all(2.0),
                                              decoration: BoxDecoration(
                                                color: MAIN_TITLE_COLOR,
                                                borderRadius:
                                                BorderRadius.circular(
                                                    8),
                                                border: Border.all(
                                                    color:
                                                    Colors.black12),
                                              ),
                                              child: Text(
                                                "${patient.TOKEN_NO}",
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10),
                                              ),
                                            )
                                                : const SizedBox(width: 70),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width:
                                    MediaQuery.of(context).size.width * .93,
                                    child: Row(
                                      //mainAxisAlignment: filteredPatientsForBind[index].ADMN_NO != "" ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                                      children: <Widget>[
                                        /// UMR,PAT_MOBILE_NO
                                        Visibility(
                                          visible: patient.UMR_NO != "",
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "${patient.UMR_NO}/",
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),

                                        ///gender
                                        Visibility(
                                          visible: patient.GENDER_CD != "",
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "${patient.GENDER_CD}/",
                                              style: SUB_TITLE.copyWith(
                                                  color: BLACK),
                                            ),
                                          ),
                                        ),

                                        ///  Formated DAte
                                        Row(
                                          children: [
                                            Visibility(
                                              visible: patient.BILL_NO != "",
                                              child: Align(
                                                child: Text(
                                                  patient.BILL_NO,
                                                  style: SUB_TITLE.copyWith(
                                                      color: BLACK),
                                                ),
                                              ),
                                            ),
                                            Visibility(
                                              visible:
                                              patient.PAT_MOBILE_NO != 0,
                                              child: Align(
                                                child: Text(
                                                  " ${patient.PAT_MOBILE_NO}",
                                                  style: SUB_TITLE.copyWith(
                                                      color: BLACK),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: <Widget>[
                                      Row(
                                        children: [
                                          Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              "Dr. ${patient.DOCTOR_NAME}",
                                              style: DR_SUB_TITLE,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                )
              ],
            ),
          ),
        ),
      );
    }
  }

  /// this Method Uses For initialise Global Variables
  Future<void> _initialiseTheGlobalVariables() async {
    await Global.initialize();
    if (Global.isAppLockEnabled && await _myLocalAuthService.checkDeviceSupportAndBiometricsAvailable()) {
      if (!Global.isAuthenticated && !isDialogShowing) {
        _checkTimeDifference(context);
      }
    }
  }

  /// This Method Used For Check the Time differnce
  Future<void> _checkTimeDifference(BuildContext context) async {
    if (Global.isAppLockEnabled) {
      if (DateTime.now().difference(Global.lastPausedTime).inSeconds >= double.parse(Global.automaticallyLockTime)) {
        Global.isAuthenticated = await _myLocalAuthService.getAuthentication(biometricOnly: false);
        if (!Global.isAuthenticated) {
          _showLockDialog(context);
        }
      }
    }
  }

  /// THis Method Used for dialog foe App Lock
  void _showLockDialog(BuildContext context) {
    if (!isDialogShowing) {
      isDialogShowing = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return WillPopScope(
            onWillPop: () async {
              return false;
            },
            child: AlertDialog(
              title: const Text('DMS+ is locked'),
              contentPadding: const EdgeInsets.only(left: 25, right: 20, top: 10, bottom: 5),
              content: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    const Text('Authentication is required to access the DMS+ app'),
                    const SizedBox(height: 10),
                    const Divider(thickness: 1, height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () async {
                            // if (_myLocalAuthService.) {
                            //   return; // Exit function if authentication is already in progress
                            // }
                            Global.isAuthenticated = await _myLocalAuthService.getAuthentication(biometricOnly: false);
                            if (Global.isAuthenticated) {
                              isDialogShowing = false;
                              Navigator.of(context).pop();
                            } else {
                              if (!isDialogShowing) {
                                Navigator.pop(context);
                                _checkTimeDifference(context);
                              }
                            }
                          },
                          child: const Text('Unlock Now'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).then((value) {
        if (Global.isAuthenticated){
          isDialogShowing = false;
        }
      });
    }
  }
}