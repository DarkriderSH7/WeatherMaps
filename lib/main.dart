import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  final TextEditingController _startTimeController = TextEditingController();

  @override
  void dispose() {
    _toController.dispose();
    _froController.dispose();
    _startTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enter Locations and Start Time'),
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
                labelText: 'From Location',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _startTimeController,
              decoration: InputDecoration(
                labelText: 'Start Time (24-hour format, e.g., 20:00)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final toLocation = _toController.text;
                final froLocation = _froController.text;
                final startTime = _startTimeController.text;

                // Fetch directions from the API
                try {
                  final directions =
                      await getDirections(froLocation, toLocation);

                  if (directions != null &&
                      directions['routes'] != null &&
                      directions['routes'].isNotEmpty) {
                    final points = decodePolyline(
                        directions['routes'][0]['overview_polyline']['points']);

                    final totalDuration =
                        directions['routes'][0]['legs'][0]['duration']['value'];
                    final travelDuration = totalDuration ~/ 60; // minutes

                    // Parse the start time
                    final startTimeParts = startTime.split(":");
                    final startHour = int.parse(startTimeParts[0]);
                    final startMinute = int.parse(startTimeParts[1]);

                    // Calculate intermediate points for 30 min intervals
                    List<int> times = [];
                    List<LatLng> locations = [];
                    for (int i = 30; i <= travelDuration; i += 30) {
                      int pointIndex =
                          (i / travelDuration * points.length).toInt();
                      times.add(i);
                      locations.add(points[pointIndex]);
                    }

                    // Fetch weather data for each interval
                    final weatherData = await fetchWeatherData(
                        locations, startHour, startMinute, times);

                    // Navigate to the second screen with weather data and route
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WeatherScreen(
                          weatherData: weatherData,
                          points: points,
                        ),
                      ),
                    );
                  } else {
                    print('No routes found for the specified locations.');
                  }
                } catch (e) {
                  print('Error fetching directions: $e');
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
        'AIzaSyDDzd6j3ZQyf1Xtl-Ic2BggOUEKCEZVrHQ'; // Replace with your Google Maps API key
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

  Future<List<Map<String, dynamic>>> fetchWeatherData(List<LatLng> locations,
      int startHour, int startMinute, List<int> times) async {
    final apiKey =
        '8048ad7b856423eff0e08e7df8062a9d'; // Replace with your OpenWeather API key
    List<Map<String, dynamic>> weatherDataList = [];

    DateTime currentTime = DateTime.now();
    DateTime journeyStartTime = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
      startHour,
      startMinute,
    );

    for (int i = 0; i < locations.length; i++) {
      final lat = locations[i].latitude;
      final lon = locations[i].longitude;

      // Adjust the timestamp for the time at this interval
      DateTime forecastTime = journeyStartTime.add(Duration(minutes: times[i]));
      int unixTime = forecastTime.millisecondsSinceEpoch ~/
          1000; // Convert to Unix timestamp

      final url = Uri.parse(
          'https://api.openweathermap.org/data/3.0/onecall?lat=$lat&lon=$lon&dt=$unixTime&exclude=minutely,daily,alerts&units=metric&appid=$apiKey');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        weatherDataList.add(data);
      } else {
        throw Exception('Failed to fetch weather data');
      }
    }

    return weatherDataList;
  }
}

// Weather Screen to display the weather information
class WeatherScreen extends StatelessWidget {
  final List<Map<String, dynamic>> weatherData;
  final List<LatLng> points;

  WeatherScreen({required this.weatherData, required this.points});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Weather Info Along the Route'),
      ),
      body: ListView.builder(
        itemCount: weatherData.length,
        itemBuilder: (context, index) {
          final data = weatherData[index];
          final temperature =
              data['current']['temp'].toStringAsFixed(1); // One decimal place
          final description = data['current']['weather'][0]['description'];
          return ListTile(
            title: Text('Weather at Interval ${index + 1}:'),
            subtitle: Text('Temperature: $temperature °C, $description'),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MapScreen(points: points),
              ),
            );
          },
          child: Text('View Route on Map'),
        ),
      ),
    );
  }
}

// Map Screen to display the Google Map with the route
class MapScreen extends StatelessWidget {
  final List<LatLng> points;

  MapScreen({required this.points});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Route Map'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: points.first,
          zoom: 10.0,
        ),
        polylines: {
          Polyline(
            polylineId: PolylineId("route"),
            points: points,
            color: Colors.blue,
            width: 5,
          ),
        },
      ),
    );
  }
}
