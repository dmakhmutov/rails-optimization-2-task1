class Task
  def initialize(result_file_path: nil, data_file_path: nil, dasable_gc: true)
    GC.disable if dasable_gc
    @result_file_path = result_file_path || 'data/result.json'
    @data_file_path = data_file_path || 'data/data_large.txt'
  end

  def parse_user(fields)
    {
      'id' => fields[1],
      'first_name' => fields[2],
      'last_name' => fields[3],
      'age' => fields[4],
    }
  end

  def parse_session(fields)
    {
      'user_id' => fields[1],
      'session_id' => fields[2],
      'browser' => fields[3].upcase,
      'time' => fields[4],
      'date' => fields[5],
    }
  end

  def collect_stats_from_user(report, user)
    user_key = "#{user.attributes['first_name']} #{user.attributes['last_name']}"
    report['usersStats'][user_key] ||= {}
    report['usersStats'][user_key] = report['usersStats'][user_key].merge(yield(user))
  end

  def work
    users, sessions = parse_file

    report = {}

    report[:totalUsers] = users.count
    # progress_bar = ProgressBar.create(total: users.count, format: '%a, %J, %E %B')

    # Подсчёт количества уникальных браузеров
    uniqueBrowsers = get_unique_browsers(sessions)
    report['uniqueBrowsersCount'] = uniqueBrowsers.count
    report['totalSessions'] = sessions.count

    report['allBrowsers'] = uniqueBrowsers.sort.join(',')

    # Статистика по пользователям
    report['usersStats'] = {}

    grouped_by_user_id_sessions = sessions.group_by { |session| session['user_id'] }
    users.each do |user|
      user_sessions = grouped_by_user_id_sessions[user['id']]
      user_object = User.new(attributes: user, sessions: user_sessions)
      prepare_stats(report, user_object)

      # progress_bar.increment
    end

    File.write(result_file_path, "#{report.to_json}\n")
  end

  private

  attr_reader :result_file_path, :data_file_path

  def parse_file
    users, sessions = [], []

    File.foreach(data_file_path) do |line|
      cols = line.split(',')
      user = parse_user(cols) if cols[0] == 'user'
      session = parse_session(cols) if cols[0] == 'session'

      users += [user] if cols[0] == 'user'
      sessions += [session] if cols[0] == 'session'
    end


    [users, sessions]
  end

  def get_unique_browsers(sessions)
    store = {}
    sessions.each { |session| store[session['browser']] = 1 }
    store.keys
  end

  def prepare_stats(report, user_object)
    collect_stats_from_user(report, user_object) do |user|
      user_times, user_browsers, user_dates = [], [], []

      user.sessions.each do |session|
        user_times += [session['time'].to_i]
        user_browsers += [session['browser']]
        user_dates += [Date.strptime(session['date'], '%F').iso8601]
      end

      {
        # Собираем количество сессий по пользователям
        'sessionsCount' => user.sessions.count,
        # Собираем количество времени по пользователям
        'totalTime' =>  "#{user_times.sum} min.",
        # Выбираем самую длинную сессию пользователя
        'longestSession' =>  "#{user_times.max} min.",
        # Браузеры пользователя через запятую
        'browsers' => user_browsers.sort.join(', '),
        # Хоть раз использовал IE?
        'usedIE' => user_browsers.any? { |b| b.match? /INTERNET EXPLORER/ },
        # Всегда использовал только Chrome?
        'alwaysUsedChrome' => user_browsers.all? { |b| b.match? /CHROME/ },
        # Даты сессий через запятую в обратном порядке в формате iso8601
        'dates' => user_dates.sort.reverse
      }
    end
  end
end
