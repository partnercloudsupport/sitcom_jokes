import 'package:sitcom_joke_app/models/movie.dart';

abstract class Joke{
  String id;
  String title;
  int likes;
  Movie movie;
  DateTime dateAdded;

  Joke({this.id, this.title, this.likes, this.movie, this.dateAdded});

  toMap();

}