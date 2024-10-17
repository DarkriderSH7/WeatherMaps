import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:numberpicker/numberpicker.dart'; // Import the numberpicker package

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Route Planner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LocationInputPage(),
      debugShowCheckedModeBanner: false, // Optional: Removes the debug banner
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
  final TextEditingController _intervalController = TextEditingController();

  int currentValue = 30; // Initial interval value

  bool isLoading = false; // Loading state

  @override
  void dispose() {
    _toController.dispose();
    _froController.dispose();
    _startTimeController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  // Function to select start time using Time Picker
  Future<void> _selectStartTime() async {
    TimeOfDay initialTime = TimeOfDay.now();
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime != null) {
      String formattedTime = pickedTime.hour.toString().padLeft(2, '0') +
          ":" +
          pickedTime.minute.toString().padLeft(2, '0');
      setState(() {
        _startTimeController.text = formattedTime;
      });
    }
  }

  // Function to select interval using Number Picker
  Future<void> _selectInterval() async {
    int tempValue = currentValue; // Temporary variable for dialog
    await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Select Interval (minutes)'),
              content: NumberPicker(
                value: tempValue,
                minValue: 1,
                maxValue: 60,
                onChanged: (value) {
                  setState(() {
                    tempValue = value;
                  });
                },
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      currentValue = tempValue; // Update main state
                      _intervalController.text =
                          currentValue.toString(); // Update TextField
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to fetch directions from Google Directions API
  Future<Map<String, dynamic>> getDirections(
      String origin, String destination) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception("GOOGLE_MAPS_API_KEY not found in .env file");
    }
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}&key=$apiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);
      if (decoded['status'] == 'OK') {
        return decoded;
      } else {
        throw Exception('Directions API error: ${decoded['status']}');
      }
    } else {
      throw Exception('Failed to fetch directions: ${response.reasonPhrase}');
    }
  }

  // Function to decode polyline into list of LatLng
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

  // Function to fetch weather data and reverse geocode region names
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

    // If the selected start time has already passed today, set it to tomorrow
    if (journeyStartTime.isBefore(currentTime)) {
      journeyStartTime = journeyStartTime.add(Duration(days: 1));
    }

    // Ensure that all forecast times are within the next 48 hours
    final maxForecastDuration = 48 * 60; // 48 hours in minutes

    for (int i = 0; i < locations.length; i++) {
      final lat = locations[i].latitude;
      final lon = locations[i].longitude;

      print('--- Interval ${i + 1} ---');
      print('Latitude: $lat, Longitude: $lon');

      DateTime forecastTime = journeyStartTime.add(Duration(minutes: times[i]));
      int forecastUnix = forecastTime.toUtc().millisecondsSinceEpoch ~/ 1000;

      // Check if forecastTime is within the next 48 hours
      final difference = forecastTime.difference(currentTime).inMinutes;
      if (difference < 0 || difference > maxForecastDuration) {
        print(
            'Forecast time for interval ${i + 1} is out of the available forecast window.');
        continue;
      }

      // Fetch weather data using One Call API's forecast
      final weatherUrl = Uri.parse(
          'https://api.openweathermap.org/data/3.0/onecall?lat=$lat&lon=$lon&exclude=minutely,daily,alerts&units=metric&appid=$weatherApiKey');
      print('Weather API URL: $weatherUrl');
      final weatherResponse = await http.get(weatherUrl);
      print('Weather API status code: ${weatherResponse.statusCode}');

      if (weatherResponse.statusCode != 200) {
        print('Failed to fetch weather data: ${weatherResponse.body}');
        continue;
      }

      final weatherData = json.decode(weatherResponse.body);

      // Extract hourly data
      List<dynamic> hourlyData = weatherData['hourly'];
      if (hourlyData == null || hourlyData.isEmpty) {
        print('No hourly weather data available.');
        continue;
      }

      // Find the closest hourly forecast
      Map<String, dynamic>? closestWeather;
      int minDifference = 999999;
      for (var hour in hourlyData) {
        int dt = hour['dt'];
        int diff = (dt - forecastUnix).abs();
        if (diff < minDifference) {
          minDifference = diff;
          closestWeather = hour;
        }
      }

      if (closestWeather == null) {
        print('No matching weather data found for forecast time.');
        continue;
      }

      // Fetch region name using Reverse Geocoding
      final geocodingUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lon&key=$geocodingApiKey');
      print('Geocoding API URL: $geocodingUrl');
      final geocodingResponse = await http.get(geocodingUrl);
      print('Geocoding API status code: ${geocodingResponse.statusCode}');

      if (geocodingResponse.statusCode != 200) {
        print('Failed to fetch region name: ${geocodingResponse.body}');
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
        'weather': closestWeather,
        'region': regionName,
        'time': forecastTime.toLocal(),
      });
    }

    return weatherAndRegionData;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Route Planner'),
      ),
      body: SingleChildScrollView(
        // To prevent overflow when keyboard appears
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "To Location" TextField
            TextField(
              controller: _toController,
              decoration: InputDecoration(
                labelText: 'To Location',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
            SizedBox(height: 20),
            // "From Location" TextField
            TextField(
              controller: _froController,
              decoration: InputDecoration(
                labelText: 'From Location',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.my_location),
              ),
            ),
            SizedBox(height: 20),
            // Start Time TextField with TimePicker
            GestureDetector(
              onTap: _selectStartTime,
              child: AbsorbPointer(
                child: TextField(
                  controller: _startTimeController,
                  decoration: InputDecoration(
                    labelText: 'Start Time (24-hour format, e.g., 20:00)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time),
                    suffixIcon: Icon(Icons.edit),
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            // Interval Picker TextField
            GestureDetector(
              onTap: _selectInterval,
              child: AbsorbPointer(
                child: TextField(
                  controller: _intervalController,
                  decoration: InputDecoration(
                    labelText: 'Interval (minutes)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timer),
                    suffixIcon: Icon(Icons.edit),
                  ),
                ),
              ),
            ),
            SizedBox(height: 30),
            // Submit Button with Loading Indicator
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final toLocation = _toController.text.trim();
                        final froLocation = _froController.text.trim();
                        final startTime = _startTimeController.text.trim();
                        final intervalText = _intervalController.text.trim();

                        // Input Validation
                        if (toLocation.isEmpty ||
                            froLocation.isEmpty ||
                            startTime.isEmpty ||
                            intervalText.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Please fill in all fields.')),
                          );
                          return;
                        }

                        // Validate Interval
                        final interval = int.tryParse(intervalText);
                        if (interval == null || interval < 1 || interval > 60) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Interval must be between 1 and 60 minutes.')),
                          );
                          return;
                        }

                        // Validate Start Time Format
                        final startTimeParts = startTime.split(":");
                        if (startTimeParts.length != 2) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Start Time must be in HH:MM format (24-hour).')),
                          );
                          return;
                        }
                        final startHour = int.tryParse(startTimeParts[0]);
                        final startMinute = int.tryParse(startTimeParts[1]);

                        if (startHour == null ||
                            startMinute == null ||
                            startHour < 0 ||
                            startHour > 23 ||
                            startMinute < 0 ||
                            startMinute > 59) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Start Time must be a valid 24-hour time (e.g., 20:00).')),
                          );
                          return;
                        }

                        setState(() {
                          isLoading = true;
                        });

                        // Fetch directions from the API
                        try {
                          final directions =
                              await getDirections(froLocation, toLocation);

                          if (directions != null &&
                              directions['routes'] != null &&
                              directions['routes'].isNotEmpty) {
                            final points = decodePolyline(directions['routes']
                                [0]['overview_polyline']['points']);

                            final totalDuration = directions['routes'][0]
                                ['legs'][0]['duration']['value'];
                            final travelDuration =
                                totalDuration ~/ 60; // minutes

                            // Calculate intermediate points for selected interval
                            List<int> times = [];
                            List<LatLng> locations = [];
                            for (int i = interval;
                                i <= travelDuration;
                                i += interval) {
                              int pointIndex =
                                  (i / travelDuration * points.length).toInt();
                              if (pointIndex >= points.length)
                                pointIndex = points.length - 1;
                              times.add(i);
                              locations.add(points[pointIndex]);
                            }

                            // Fetch weather data and reverse geocode region names
                            final weatherAndRegionData =
                                await fetchWeatherAndRegionData(
                                    locations, startHour, startMinute, times);

                            if (weatherAndRegionData.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'No weather data available for the selected intervals.')),
                              );
                              setState(() {
                                isLoading = false;
                              });
                              return;
                            }

                            // Navigate to the second screen with weather data, region names, and route
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WeatherScreen(
                                  weatherAndRegionData: weatherAndRegionData,
                                  points: points,
                                  intervalLocations: locations,
                                  interval: interval, // Pass the interval here
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'No routes found for the specified locations.')),
                            );
                          }
                        } catch (e) {
                          print('Error fetching directions: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Error fetching directions. Please try again.')),
                          );
                        }

                        setState(() {
                          isLoading = false;
                        });
                      },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  textStyle: TextStyle(fontSize: 18),
                ),
                child: isLoading
                    ? CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )
                    : Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Weather Screen to display the weather information along with region names
class WeatherScreen extends StatelessWidget {
  final List<Map<String, dynamic>> weatherAndRegionData;
  final List<LatLng> points;
  final List<LatLng> intervalLocations;
  final int interval;

  WeatherScreen({
    required this.weatherAndRegionData,
    required this.points,
    required this.intervalLocations,
    required this.interval,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Weather Info Along the Route'),
      ),
      body: weatherAndRegionData.isEmpty
          ? Center(
              child: Text(
                'No weather data available.',
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: weatherAndRegionData.length,
              itemBuilder: (context, index) {
                final data = weatherAndRegionData[index];
                final weather = data['weather'];
                final region = data['region'];
                final time = data['time'];
                final temperature =
                    weather['temp'].toStringAsFixed(1); // One decimal place
                final description = weather['weather'][0]['description'];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: Icon(Icons.cloud),
                    title: Text('Interval ${index + 1}: $region'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Temperature: $temperature °C'),
                        Text('Description: $description'),
                        Text('Time: ${time.toLocal()}'),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MapScreen(
                  points: points,
                  intervalLocations: intervalLocations,
                  interval: interval,
                ),
              ),
            );
          },
          icon: Icon(Icons.map),
          label: Text('View Route on Map'),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: 15),
            textStyle: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}

// Map Screen to display the Google Map with the route and markers
class MapScreen extends StatelessWidget {
  final List<LatLng> points;
  final List<LatLng> intervalLocations;
  final int interval;

  MapScreen({
    required this.points,
    required this.intervalLocations,
    required this.interval,
  });

  @override
  Widget build(BuildContext context) {
    Set<Polyline> polylines = {
      Polyline(
        polylineId: PolylineId("route"),
        points: points,
        color: Colors.blue,
        width: 5,
      ),
    };

    Set<Marker> markers = intervalLocations.asMap().entries.map((entry) {
      int index = entry.key;
      LatLng point = entry.value;
      return Marker(
        markerId: MarkerId('interval_marker_$index'),
        position: point,
        infoWindow: InfoWindow(
          title: 'Interval ${index + 1}',
          snippet: 'Location for $interval-minute interval',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      );
    }).toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text('Route Map'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: points.first,
          zoom: 10.0,
        ),
        polylines: polylines,
        markers: markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
}
