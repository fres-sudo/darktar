import 'dart:async';
import 'dart:collection';

/// A simple in-memory job queue for background task processing.
///
/// Jobs are processed sequentially in FIFO order using Dart isolates
/// for CPU-intensive tasks like documentation generation.
class JobQueue {
  JobQueue({this.maxConcurrent = 1});

  final int maxConcurrent;
  final Queue<Job> _pending = Queue();
  final List<Job> _running = [];
  final StreamController<JobEvent> _eventController =
      StreamController.broadcast();

  /// Stream of job events (started, completed, failed).
  Stream<JobEvent> get events => _eventController.stream;

  /// Number of pending jobs.
  int get pendingCount => _pending.length;

  /// Number of running jobs.
  int get runningCount => _running.length;

  /// Enqueues a job for processing.
  void enqueue(Job job) {
    _pending.add(job);
    _eventController.add(JobEnqueued(job));
    _processNext();
  }

  /// Processes the next job if capacity allows.
  void _processNext() {
    if (_running.length >= maxConcurrent || _pending.isEmpty) {
      return;
    }

    final job = _pending.removeFirst();
    _running.add(job);
    _eventController.add(JobStarted(job));

    job.execute().then((_) {
      _running.remove(job);
      _eventController.add(JobCompleted(job));
      _processNext();
    }).catchError((Object error, StackTrace stack) {
      _running.remove(job);
      _eventController.add(JobFailed(job, error, stack));
      _processNext();
    });
  }

  /// Shuts down the queue and cancels pending jobs.
  Future<void> shutdown() async {
    _pending.clear();
    await _eventController.close();
  }
}

/// Base class for background jobs.
abstract class Job {
  Job({required this.id, required this.type});

  /// Unique job identifier.
  final String id;

  /// Job type for logging/tracking.
  final String type;

  /// Executes the job. Implementations should handle their own errors.
  Future<void> execute();

  @override
  String toString() => 'Job($type: $id)';
}

/// Base class for job events.
sealed class JobEvent {
  const JobEvent(this.job);
  final Job job;
}

/// Emitted when a job is added to the queue.
class JobEnqueued extends JobEvent {
  const JobEnqueued(super.job);
}

/// Emitted when a job starts executing.
class JobStarted extends JobEvent {
  const JobStarted(super.job);
}

/// Emitted when a job completes successfully.
class JobCompleted extends JobEvent {
  const JobCompleted(super.job);
}

/// Emitted when a job fails.
class JobFailed extends JobEvent {
  const JobFailed(super.job, this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}
