require 'csv'

# Usage examples
#  $ ruby report_verifier.rb enrollment_file.csv report_file.csv 2012/03/01 2012/03/8 2012/03/15 2012/03/22 
#  To put output into text file
#  $ ruby report_verifier.rb enrollment_file.csv report_file.csv 2012/03/01 2012/03/8 2012/03/15 2012/03/22 > outit.txt


class ReportVerifier
  attr_accessor :data_file, :enrollment_file, :patients

  def initialize(enrollment_file, data_file, dates, file_reader) 
    puts "#{data_file};;; #{enrollment_file};;; #{dates};;;"
    @file_reader = file_reader
    @enrollment_file = enrollment_file 
    @data_file = data_file 
    @patients = Patients.new(
      *dates.map { |dt_string| to_time_yyyy_mm_dd(dt_string) } ) 
  end
 
  def process
    data = @file_reader.read(@data_file)
    enrollments = @file_reader.read(@enrollment_file)
    
    if process_data(data)
      if process_enrollments(enrollments)
        verify 
      end
    end
  end 

  def process_data(data)
    if data.empty?
      puts "No Patient Data available in report"
      return false
    end
    name_idx, date_idx, service_idx = setup_data_indexes(data[0])
    data.each do |row|
      patients.add_visit(row[name_idx], 
                          to_time_yyyy_mm_dd(row[date_idx]), 
                          row[service_idx][0..1])
    end
    true
  end

  def process_enrollments(data)
    if data.empty?
      puts "No Enrollment Data available"
      return false
    end
    name_idx, start_date_idx, end_date_idx = setup_enrollment_indexes(data[0])
    data.each do |row|
      patients.add_enrollment(row[name_idx],
                               to_time_mm_dd_yyyy(row[start_date_idx]),
                               to_time_mm_dd_yyyy(row[end_date_idx]))
    end
    true 
  end
  
  def verify
    people_count = 0 
    patients.patient_visits.each do |person|
      unless person.valid?
        puts "\n\nPerson to look into : #{person}" 
        puts "Reasons:#{person.invalid_reasons.join("; ")};"
        people_count += 1
      end
    end
    puts "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    puts "\n\nNumber of people to look into:#{people_count};\n\n"
  end
  

  private 

  def to_time_yyyy_mm_dd(dt_string)
    Time.local(*dt_string.split("/"))
  end

  def to_time_mm_dd_yyyy(dt_string)
    unless dt_string.nil?
      parts = dt_string.split("/")
      to_time_yyyy_mm_dd([parts[2], parts[0], parts[1]].join("/"))
    end
  end

  def setup_data_indexes(row) 
    start_indicator = "Service Type"
    name_idx = row.find_index {|col| col == start_indicator } + 1
    date_idx = name_idx + 1
    service_idx = date_idx + 1
    [name_idx, date_idx, service_idx]
  end

  def setup_enrollment_indexes(row)
    start_indicator = "Episode End"
    name_idx = row.find_index {|col| col == start_indicator } + 3
    start_date_idx = name_idx + 3
    end_date_idx = start_date_idx + 1
    [name_idx, start_date_idx, end_date_idx]
  end
end

class Patients
  attr_accessor :patient_visits
  attr_accessor :wk1, :wk2, :wk3, :wk4, :wk5

  def initialize(wk1, wk2, wk3, wk4)
    @patient_visits = [] 
    @wk1, @wk2, @wk3, @wk4 = wk1, wk2, wk3, wk4 
    @wk5 = Time.local(wk4.year, wk4.month, wk4.day + 7)
  end

  def add_visit(name, date, service_type)
    patient_visit = find_or_create(name)
    patient_visit.add_visit(date, service_type)
  end

  def add_enrollment(name, start_date, end_date)
    patient = find(name)
    patient.add_enrollment(start_date, end_date) if patient
  end

  def get_week(visit_date)
    if wk1 <= visit_date && wk2 > visit_date 
      1
    elsif wk2 <= visit_date && wk3 > visit_date 
      2
    elsif wk3 <= visit_date && wk4 > visit_date 
      3
    else
      4
    end
  end

  def dates_between_week?(start_enrollment, end_enrollment, week)
    case week
    when 1 
      wk1 >= start_enrollment && (end_enrollment.nil? || wk2 <= end_enrollment)
    when 2 
      wk2 >= start_enrollment && (end_enrollment.nil? || wk3 <= end_enrollment)
    when 3 
      wk3 >= start_enrollment && (end_enrollment.nil? || wk4 <= end_enrollment)
    when 4 
      wk4 >= start_enrollment && (end_enrollment.nil? || wk5 <= end_enrollment)
    else
      false 
    end
  end

  private

  def find(name)
    patient_visits.find {|pv| pv.name == name }
  end

  def find_or_create(name)
    patient_visit = patient_visits.find {|pv| pv.name == name }
    unless patient_visit
      patient_visit = PatientVisits.new(name, self)
      patient_visits << patient_visit
    end
    patient_visit
  end
end

class PatientVisits
  attr_accessor :name, :visits_by_week_and_type, :enrollments

  def initialize(name, container) 
    @name = name
    @container = container
    @visits_by_week_and_type = { 1 => Hash.new { 0 }, 2 => Hash.new { 0 }, 
                                 3 => Hash.new { 0 }, 4 => Hash.new { 0 } }
    @enrollments = []
  end

  def add_enrollment(start_date, end_date)
    enrollments << [start_date, end_date]
    enrollments.sort! { |a1, a2| a1[0] <=> a2[0] }
  end

  def add_visit(visit_date, visit_type)
    visits_by_week_and_type[@container.get_week(visit_date)][visit_type] += 1
  end

  def to_s
    enrollment_text = enrollments.map {|a| "Enrolled: #{a[0]} to #{a[1]}"}.join(" + ")
    %Q{#{@name}\n\t #{enrollment_text}; -- week/type counts:#{visits_by_week_and_type.inspect} }
  end

  def enrolled_during?(week)
    return false if enrollments.empty?

    enrollments.any? do |start_enrollment, end_enrollment|
      @container.dates_between_week?(start_enrollment, end_enrollment, week)
    end
  end

  def visit_count(week, type) 
    visits_by_week_and_type[week][type] 
  end 

  def months_visit_count(type)
    (1..4).to_a.inject(0) { |sum, wk| sum + visits_by_week_and_type[wk][type] }
  end

  def validate_weekly_types(enrolled_during)
    # must have at least 1 per week for SN and HA
    reasons = []
    one_per_week_types = ['SN', 'HA']
    (1..4).to_a.each do |week|
      if enrolled_during[week - 1]
        one_per_week_types.each do |type|
          reasons << "Week #{week} #{type} visits" if visit_count(week, type) < 1
        end
      end
    end
    reasons
  end

  def validate_monthly_types(enrolled_during)
    # must have at least 1 per month for SW and SC
    reasons = []
    return reasons unless enrolled_during.all?
    ['SW', 'SC'].each do |type|
      reasons << "Monthly #{type} visits" if months_visit_count(type) < 1
    end
    reasons
  end

  def valid?
    @reasons = []
    enrolled_during = (1..4).to_a.map {|wk| enrolled_during?(wk) }
    @reasons += validate_weekly_types(enrolled_during)
    @reasons += validate_monthly_types(enrolled_during)

    @reasons.empty?
  end

  def invalid_reasons
    @reasons
  end
end


#!!!!!!! DO IT !!!!!!!!!!!!!!!!!!!!!!
puts "ARGV:#{ARGV};"
verifier = ReportVerifier.new(ARGV.delete_at(0), ARGV.delete_at(0), ARGV, CSV)
verifier.process
