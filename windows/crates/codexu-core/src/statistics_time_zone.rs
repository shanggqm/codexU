use chrono::{
    offset::LocalResult, DateTime, Datelike, Duration, Local, NaiveDate, NaiveTime, TimeZone, Utc,
};

#[derive(Debug, Clone, Copy)]
pub enum StatisticsTimeZone {
    Local,
    Named(chrono_tz::Tz),
}

impl StatisticsTimeZone {
    pub(crate) fn date(&self, date: DateTime<Utc>) -> NaiveDate {
        match self {
            Self::Local => date.with_timezone(&Local).date_naive(),
            Self::Named(tz) => date.with_timezone(tz).date_naive(),
        }
    }
    pub(crate) fn day_key(&self, date: DateTime<Utc>) -> String {
        self.date(date).format("%Y-%m-%d").to_string()
    }
    pub(crate) fn identity(&self) -> String {
        match self {
            Self::Local => format!("local:{}", Local::now().offset()),
            Self::Named(tz) => tz.name().to_string(),
        }
    }
    pub(crate) fn month_start(&self, date: DateTime<Utc>) -> DateTime<Utc> {
        let day = self.date(date).day() as i64;
        self.days_before_start(date, day - 1)
    }
    pub(crate) fn day_start(&self, date: DateTime<Utc>) -> DateTime<Utc> {
        match self {
            Self::Local => day_start_in_timezone(date, &Local),
            Self::Named(timezone) => day_start_in_timezone(date, timezone),
        }
    }

    pub(crate) fn days_before_start(&self, date: DateTime<Utc>, day_count: i64) -> DateTime<Utc> {
        if day_count <= 0 {
            return self.day_start(date);
        }
        match self {
            Self::Local => {
                let local_day = date.with_timezone(&Local).date_naive() - Duration::days(day_count);
                to_midnight_utc_from_date(local_day, &Local)
                    .or_else(|| to_midnight_utc_from_date(local_day + Duration::days(1), &Local))
                    .unwrap_or_else(|| self.day_start(date))
            }
            Self::Named(timezone) => {
                let local_day =
                    date.with_timezone(timezone).date_naive() - Duration::days(day_count);
                to_midnight_utc_from_date(local_day, timezone)
                    .or_else(|| to_midnight_utc_from_date(local_day + Duration::days(1), timezone))
                    .unwrap_or_else(|| self.day_start(date))
            }
        }
    }

    pub(crate) fn next_day_start(&self, date: DateTime<Utc>) -> DateTime<Utc> {
        match self {
            Self::Local => {
                let next_local_day = date.with_timezone(&Local).date_naive() + Duration::days(1);
                next_midnight_utc(next_local_day, &Local).unwrap_or(date)
            }
            Self::Named(timezone) => {
                let next_local_day = date.with_timezone(timezone).date_naive() + Duration::days(1);
                next_midnight_utc(next_local_day, timezone).unwrap_or(date)
            }
        }
    }

    pub(crate) fn calendar_day_distance(&self, start: DateTime<Utc>, end: DateTime<Utc>) -> i64 {
        match self {
            Self::Local => end
                .with_timezone(&Local)
                .date_naive()
                .signed_duration_since(start.with_timezone(&Local).date_naive())
                .num_days(),
            Self::Named(timezone) => end
                .with_timezone(timezone)
                .date_naive()
                .signed_duration_since(start.with_timezone(timezone).date_naive())
                .num_days(),
        }
    }
}

fn day_start_in_timezone<Tz: TimeZone>(date: DateTime<Utc>, timezone: &Tz) -> DateTime<Utc> {
    let local = date.with_timezone(timezone);
    to_midnight_utc_from_date(local.date_naive(), timezone).unwrap_or(date)
}

fn next_midnight_utc<Tz: TimeZone>(date: NaiveDate, timezone: &Tz) -> Option<DateTime<Utc>> {
    to_midnight_utc_from_date(date, timezone)
        .or_else(|| to_midnight_utc_from_date(date + Duration::days(1), timezone))
}

fn to_midnight_utc_from_date<Tz: TimeZone>(
    date: NaiveDate,
    timezone: &Tz,
) -> Option<DateTime<Utc>> {
    let local_midnight = NaiveTime::from_hms_opt(0, 0, 0).unwrap();
    let mut local = date.and_time(local_midnight);
    loop {
        match timezone.from_local_datetime(&local) {
            LocalResult::Single(datetime) => return Some(datetime.with_timezone(&Utc)),
            LocalResult::Ambiguous(earliest, _) => return Some(earliest.with_timezone(&Utc)),
            LocalResult::None => {
                local += Duration::minutes(1);
                if local.date() != date {
                    return None;
                }
            }
        }
    }
}
