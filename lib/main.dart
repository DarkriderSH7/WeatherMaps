import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
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

                    // Fetch weather data and reverse geocode region names
                    final weatherAndRegionData =
                        await fetchWeatherAndRegionData(
                            locations, startHour, startMinute, times);

                    // Navigate to the second screen with weather data, region names, and route
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WeatherScreen(
                          weatherAndRegionData: weatherAndRegionData,
                          points: points,
                          intervalLocations: locations,
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
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
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

  Future<List<Map<String, dynamic>>> fetchWeatherAndRegionData(
      List<LatLng> locations,
      int startHour,
      int startMinute,
      List<int> times) async {
    final weatherApiKey = dotenv.env['OPEN_WEATHER_MAP_API_KEY'];
    final geocodingApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    List<Map<String, dynamic>> weatherAndRegionData = [];

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

      print('--- Interval ${i + 1} ---');
      print('Latitude: $lat, Longitude: $lon');

      DateTime forecastTime = journeyStartTime.add(Duration(minutes: times[i]));
      int unixTime = forecastTime.millisecondsSinceEpoch ~/ 1000;

      // Fetch weather data
      final weatherUrl = Uri.parse(
          'https://api.openweathermap.org/data/3.0/onecall?lat=$lat&lon=$lon&dt=$unixTime&exclude=minutely,daily,alerts&units=metric&appid=$weatherApiKey');
      print('Weather API URL: $weatherUrl');
      final weatherResponse = await http.get(weatherUrl);
      print('Weather API status code: ${weatherResponse.statusCode}');

      if (weatherResponse.statusCode != 200) {
        print('Failed to fetch weather data');
        continue;
      }

      final weatherData = json.decode(weatherResponse.body);

      // Fetch region name using Reverse Geocoding
      final geocodingUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lon&key=$geocodingApiKey');
      print('Geocoding API URL: $geocodingUrl');
      final geocodingResponse = await http.get(geocodingUrl);
      print('Geocoding API status code: ${geocodingResponse.statusCode}');

      if (geocodingResponse.statusCode != 200) {
        print('Failed to fetch region name');
        continue;
      }

      final geocodingData = json.decode(geocodingResponse.body);
      print('Geocoding API response: ${geocodingData}');

      String regionName = 'Unknown Region';

      if (geocodingData['status'] == 'OK' &&
          geocodingData['results'].isNotEmpty) {
        try {
          final components = geocodingData['results'][0]['address_components'];
          print('Address components: $components');

          var regionComponent;
          List<String> desiredTypes = [
            'locality',
            'sublocality',
            'postal_town',
            'neighborhood',
            'administrative_area_level_2',
            'administrative_area_level_1',
            'country'
          ];

          for (var type in desiredTypes) {
            regionComponent = components.firstWhere(
              (component) {
                List<dynamic> types = component['types'] as List<dynamic>;
                return types.contains(type);
              },
              orElse: () => null,
            );

            if (regionComponent != null) {
              regionName = regionComponent['long_name'];
              print('Found region name: $regionName');
              break;
            }
          }

          // Fallback to formatted address
          if (regionComponent == null) {
            regionName = geocodingData['results'][0]['formatted_address'];
            print('Using formatted address as region name: $regionName');
          }
        } catch (e) {
          print('Error extracting region name: $e');
        }
      } else {
        print('Geocoding API returned status: ${geocodingData['status']}');
        if (geocodingData.containsKey('error_message')) {
          print(
              'Geocoding API error message: ${geocodingData['error_message']}');
        }
      }

      weatherAndRegionData.add({
        'weather': weatherData,
        'region': regionName,
        'time': forecastTime.toLocal(),
      });
    }

    return weatherAndRegionData;
  }
}

// Weather Screen to display the weather information along with region names
class WeatherScreen extends StatelessWidget {
  final List<Map<String, dynamic>> weatherAndRegionData;
  final List<LatLng> points;
  final List<LatLng> intervalLocations;

  WeatherScreen(
      {required this.weatherAndRegionData,
      required this.points,
      required this.intervalLocations});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Weather Info Along the Route'),
      ),
      body: ListView.builder(
        itemCount: weatherAndRegionData.length,
        itemBuilder: (context, index) {
          final data = weatherAndRegionData[index];
          final weather = data['weather'];
          final region = data['region'];
          final time = data['time'];
          final temperature = weather['current']['temp']
              .toStringAsFixed(1); // One decimal place
          final description = weather['current']['weather'][0]['description'];
          return ListTile(
            title: Text('Weather at Interval ${index + 1}: $region'),
            subtitle: Text(
                'Temperature: $temperature °C, $description\nTime: ${time.toLocal()}'),
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
                builder: (context) => MapScreen(
                    points: points, intervalLocations: intervalLocations),
              ),
            );
          },
          child: Text('View Route on Map'),
        ),
      ),
    );
  }
}

// Map Screen to display the Google Map with the route and markers
class MapScreen extends StatelessWidget {
  final List<LatLng> points;
  final List<LatLng> intervalLocations;

  MapScreen({required this.points, required this.intervalLocations});

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
        markers: intervalLocations.asMap().entries.map((entry) {
          int index = entry.key;
          LatLng point = entry.value;
          return Marker(
            markerId: MarkerId('interval_marker_$index'),
            position: point,
            infoWindow: InfoWindow(
              title: 'Interval ${index + 1}',
              snippet: 'Location for 30-minute interval',
            ),
          );
        }).toSet(),
      ),
    );
  }
}
