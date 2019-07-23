require 'open3'
require 'tap_parser'
require 'audit'
require 'headless'

class RacketStyleGrader < Grader
  def autograde?
    true
  end

  def display_type
    "Racket Style"
  end
  
  def to_s
    if self.upload
      "#{self.avail_score} points: Run Racket style checker, using #{self.upload.file_name}"
    else
      "#{self.avail_score} points: Run Racket style checker"
    end
  end

  after_initialize :load_style_params
  before_validation :set_style_params

  def assign_attributes(attrs)
    super
    set_style_params
  end

  def export_data
    tb = SubTarball.new(self.assignment)
    tb.update_with!(
      self.assignment.used_submissions.includes(:users, :grades).where("grades.grader_id": self.id).map do |s|
        g = s.grades.first.grading_output_path
        ["#{s.id}#{File.extname(g)}", g]
      end.to_h
    )
    tb
  end
  def export_data_schema
    <<-schema
An archive containing:
  <submissionId>.tap: the current TAP output for each submission
     OR
  <submissionId>.log: the current log file if there is no TAP output
schema
  end
  def import_data_schema
    <<-schema
An archive containing:
  <submissionId>.tap: the updated TAP output for each submission
                      or the string "DELETE" to erase the grade
schema
  end
  
  protected
  
  def do_grading(assignment, sub)
    g = self.grade_for sub
    Dir.mktmpdir("grade-#{sub.id}-#{g.id}_") do |tmpdir|
      @tmpdir = tmpdir
      sub.upload.extract_contents_to!(nil, Pathname.new(tmpdir))
      Headless.ly(display: g.id % Headless::MAX_DISPLAY_NUMBER, autopick: true) do
        run_command_produce_tap assignment, sub, timeout: Grader::DEFAULT_GRADING_TIMEOUT do |prefix, err, g, tap|
          if err
            record_compile_error(sub, g)
          else
            record_tap_as_comments(g, tap, sub)
          end
        end
      end
    end
  end

  def get_command_arguments(assignment, sub)
    [
      "style.tap",
      {"XDG_RUNTIME_DIR" => nil},
      ["racket", Rails.root.join("lib/assets/checkstyle.rkt").to_s,
       "--max-points", self.avail_score.to_s,
       "--line-width", self.line_length.to_s,
       @tmpdir],
      [[@tmpdir, Upload.upload_path_for(sub.upload.extracted_path.to_s)]].to_h
    ]
  end

  def load_style_params
    return if new_record?
    self.line_length = self.params.to_i
  end

  def set_style_params
    self.params = "#{self.line_length}"
  end

  def recompute_grades
    # nothing to do:
    # we already compute the score here based on the TAP output
  end

end
