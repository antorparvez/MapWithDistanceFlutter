import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Polyline example',
      theme: ThemeData(
        primarySwatch: Colors.orange,
      ),
      home: MapScreen(),
    );
  }
}


class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  TextEditingController destLatController = TextEditingController();
  TextEditingController destLongController = TextEditingController();

  double _originLatitude = 0.0, _originLongitude = 0.0;
  double _destLatitude = 0.0, _destLongitude = 0.0;

  Map<MarkerId, Marker> markers = {};
  Map<PolylineId, Polyline> polylines = {};
  List<LatLng> polylineCoordinates = [];
  PolylinePoints polylinePoints = PolylinePoints();
  String googleAPiKey = "";///// todo ADD YOUR KEY HERE AND MANIFEST

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_originLatitude, _originLongitude),
                      zoom: 15,
                    ),
                    myLocationEnabled: true,
                    tiltGesturesEnabled: true,
                    compassEnabled: true,
                    scrollGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                    onMapCreated: _onMapCreated,
                    markers: Set<Marker>.of(markers.values),
                    polylines: Set<Polyline>.of(polylines.values),
                  ),
                  Positioned(
                    bottom: 16.0,
                    left: 16.0,
                    child: Text(
                      "Current Location: $_originLatitude, $_originLongitude",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Column(
                children: [
                  TextField(
                    controller: destLatController,
                    decoration: InputDecoration(labelText: 'Destination Latitude'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: destLongController,
                    decoration: InputDecoration(labelText: 'Destination Longitude'),
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(height: 16.0),
                  ElevatedButton(
                    onPressed: _onCalculateRoute,
                    child: Text('Calculate Route'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) async {
    mapController = controller;
  }

  _addMarker(LatLng position, String id, BitmapDescriptor descriptor) {
    MarkerId markerId = MarkerId(id);
    Marker marker = Marker(markerId: markerId, icon: descriptor, position: position);
    markers[markerId] = marker;
  }

  _addPolyLine() {
    PolylineId id = PolylineId("poly");
    Polyline polyline = Polyline(
        polylineId: id, color: Colors.purpleAccent, points: polylineCoordinates, width: 4,);
    polylines[id] = polyline;
    setState(() {});
  }

  _onCalculateRoute() async {
    BitmapDescriptor customDestinationIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(devicePixelRatio: 2.5), // Adjust devicePixelRatio as needed
      'assets/destination_icon.png', // Path to your custom marker icon asset
    );
    setState(() {
      _destLatitude = double.parse(destLatController.text);
      _destLongitude = double.parse(destLongController.text);
      markers.clear();

      polylines.clear();
      polylineCoordinates.clear();
      _addMarker(
          LatLng(_destLatitude, _destLongitude), "destination", customDestinationIcon);
    });

    await _getCurrentLocation();
    await _getPolyline();
  }

  Future<void> _requestLocationPermission() async {
    PermissionStatus status = await Permission.location.request();
    if (status != PermissionStatus.granted) {
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text('Location Permission Required'),
          content: Text('Please grant location access to use this feature.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    } else {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _originLatitude = position.latitude;
      _originLongitude = position.longitude;
    });

    print("_originLatitude --- $_originLatitude");
    print("_originLongitude --- $_originLongitude");

    // Add marker for current location
    _addMarker(
        LatLng(_originLatitude, _originLongitude), "origin", BitmapDescriptor.defaultMarker);

    mapController.animateCamera(CameraUpdate.newLatLng(LatLng(_originLatitude, _originLongitude)));
  }

  Future<void> _getPolyline() async {
    String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$_originLatitude,$_originLongitude'
        '&destination=$_destLatitude,$_destLongitude&mode=driving&key=$googleAPiKey';

    http.Response response = await http.get(Uri.parse(url));
    Map<String, dynamic> data = json.decode(response.body);

    if (data['status'] == 'OK') {
      List<LatLng> decodedPolyline = _decodePoly(data['routes'][0]['overview_polyline']['points']);

      setState(() {
        polylineCoordinates.addAll(decodedPolyline);
        _addPolyLine();
      });

      // Get bounds of polyline
      LatLngBounds bounds = _getPolylineBounds(decodedPolyline);

      // Animate camera to polyline bounds
      mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } else {
      print('Error: ${data['status']}');
    }
  }

  LatLngBounds _getPolylineBounds(List<LatLng> polyline) {
    double minLat = double.infinity;
    double minLong = double.infinity;
    double maxLat = -double.infinity;
    double maxLong = -double.infinity;

    for (LatLng point in polyline) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLong) minLong = point.longitude;
      if (point.longitude > maxLong) maxLong = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLong),
      northeast: LatLng(maxLat, maxLong),
    );
  }


  List<LatLng> _decodePoly(String encoded) {
    List<PointLatLng> decoded = polylinePoints.decodePolyline(encoded);
    return decoded.map((PointLatLng point) => LatLng(point.latitude, point.longitude)).toList();
  }
}

