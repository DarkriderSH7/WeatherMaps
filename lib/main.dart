import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For decoding JSON

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Location Input',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LocationInputPage(),
    );
  }
}

class LocationInputPage extends StatefulWidget {
  @override
  _LocationInputPageState createState() => _LocationInputPageState();
}

class _LocationInputPageState extends State<LocationInputPage> {
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _froController = TextEditingController();

  @override
  void dispose() {
    _toController.dispose();
    _froController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enter Locations'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _toController,
              decoration: InputDecoration(
                labelText: 'To Location',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _froController,
              decoration: InputDecoration(
                labelText: 'For Location',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final toLocation = _toController.text;
                final froLocation = _froController.text;

                // Fetch directions from the API
                final directions = await getDirections(froLocation, toLocation);

                if (directions != null &&
                    directions['routes'] != null &&
                    directions['routes'].isNotEmpty) {
                  final points = decodePolyline(
                      directions['routes'][0]['overview_polyline']['points']);

                  // Navigate to the second screen and pass the polyline points
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapScreen(points: points),
                    ),
                  );
                } else {
                  print('No routes found for the specified locations.');
                }
              },
              child: Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> getDirections(
      String origin, String destination) async {
    final apiKey =
        'AIzaSyDDzd6j3ZQyf1Xtl-Ic2BggOUEKCEZVrHQ'; // Replace with your actual API Key
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$apiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch directions');
    }
  }

  // Decode the polyline into LatLng points
  List<LatLng> decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble()));
    }
    return poly;
  }
}

// This is the second screen where the map with the route is displayed
class MapScreen extends StatefulWidget {
  final List<LatLng> points;

  MapScreen({required this.points});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  final Set<Polyline> _polylines = {};
  final LatLng _initialPosition =
      const LatLng(43.6532, -79.3832); // Default to Toronto

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;

    // Add polyline to the map
    setState(() {
      _polylines.add(Polyline(
        polylineId: PolylineId("route"),
        points: widget.points,
        width: 5,
        color: Colors.blue,
      ));
    });

    // Move the camera to the start of the polyline route
    if (widget.points.isNotEmpty) {
      mapController.animateCamera(CameraUpdate.newLatLng(widget.points.first));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Route Map'),
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        polylines: _polylines,
        initialCameraPosition: CameraPosition(
          target: _initialPosition,
          zoom: 12.0,
        ),
      ),
    );
  }
}
